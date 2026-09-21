import Darwin
import Foundation
import Testing

@testable import NetKit

/// A listening socket on the loopback, so the scanner has something to find.
private final class LocalListener {
    let fd: Int32
    let port: UInt16

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(descriptor, 16) == 0 else { throw ToolError(errno: errno) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(descriptor, $0, &length) }
        }
        fd = descriptor
        port = UInt16(bigEndian: address.sin_port)
    }

    deinit { close(fd) }
}

@Suite("Port scanner")
struct PortScannerTests {
    private let loopback = ResolvedAddress(literal: "127.0.0.1")!

    @Test func findsAnOpenPortAndARefusedOne() async throws {
        let listener = try LocalListener()
        // A second listener, closed at once, gives a port nobody listens on.
        let closedPort = try { () throws -> UInt16 in
            let temporary = try LocalListener()
            return temporary.port
        }()
        var states: [Int: PortState] = [:]
        var lastProgress: (Int, Int)?
        var finished = false
        for await event in PortScanner.run(address: loopback, ports: [Int(listener.port), Int(closedPort)]) {
            switch event {
            case .result(let port, let state, _): states[port] = state
            case .progress(let done, let total): lastProgress = (done, total)
            case .finished: finished = true
            default: break
            }
        }
        #expect(states[Int(listener.port)] == .open)
        #expect(states[Int(closedPort)] == .closed)
        #expect(lastProgress?.0 == 2 && lastProgress?.1 == 2)
        #expect(finished)
    }

    @Test func tcpPingFallbackMeasuresAHandshake() async throws {
        let listener = try LocalListener()
        let result = try await TCPProbe.once(address: loopback, port: listener.port, timeoutMilliseconds: 500)
        guard case .open(let milliseconds) = result else {
            Issue.record("expected open, got \(result)")
            return
        }
        #expect(milliseconds < 500)
    }

    @Test func stopsWhenTheRunIsCancelled() async throws {
        // 20 000 ports of a TEST-NET address would take a long time. Cancelling
        // must end the run at once.
        let address = try #require(ResolvedAddress(literal: "192.0.2.1"))
        let ports = Array(1...5000)
        let task = Task { () -> Int in
            var count = 0
            for await event in PortScanner.run(address: address, ports: ports, timeoutMilliseconds: 5000) {
                if case .result = event { count += 1 }
            }
            return count
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let started = ContinuousClock.now
        _ = await task.value
        #expect(ContinuousClock.now - started < .seconds(2))
    }
}
