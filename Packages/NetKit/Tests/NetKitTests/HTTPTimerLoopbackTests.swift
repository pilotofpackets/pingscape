import Foundation
import Network
import Synchronization
import Testing

@testable import NetKit

/// A plain HTTP server on the loopback interface that answers each request
/// with what `respond` returns for its path, then closes the connection.
final class LoopbackHTTPServer: Sendable {
    /// The paths asked for, in order.
    final class Log: Sendable {
        let paths = Mutex<[String]>([])
        var count: Int { paths.withLock { $0.count } }
    }

    private let listener: NWListener
    let requests = Log()

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(respond: @escaping @Sendable (String) -> String) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let requests = requests
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                requests.paths.withLock { $0.append(path) }
                connection.send(
                    content: Data(respond(path).utf8),
                    completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let ready = Mutex(false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    if !ready.withLock({ old in defer { old = true }; return old }) { continuation.resume() }
                default: break
                }
            }
            listener.start(queue: .global())
        }
    }

    func stop() { listener.cancel() }

    static func response(_ status: String, headers: [String: String] = [:], body: String = "") -> String {
        var lines = ["HTTP/1.1 \(status)", "Content-Length: \(body.utf8.count)", "Connection: close"]
        lines += headers.map { "\($0.key): \($0.value)" }
        return lines.joined(separator: "\r\n") + "\r\n\r\n" + body
    }
}

@Suite("HTTP timing on this machine", .serialized)
struct HTTPTimerLoopbackTests {
    @Test("One request: status, protocol, address and phases, but no DNS or TLS")
    func single() async throws {
        let server = try await LoopbackHTTPServer { _ in LoopbackHTTPServer.response("200 OK", body: "hello") }
        defer { server.stop() }
        let steps = try await HTTPTimer.measure(URL(string: "http://127.0.0.1:\(server.port)/")!)
        #expect(steps.count == 1)
        let step = try #require(steps.first)
        #expect(step.statusCode == 200)
        #expect(step.networkProtocol == "http/1.1")
        #expect(step.remoteAddress == "127.0.0.1")
        #expect(step.remotePort == Int(server.port))
        #expect(step.tlsMilliseconds == nil, "Plain HTTP has no TLS phase")
        #expect(step.totalMilliseconds.map { $0 >= 0 } == true)
        #expect(step.url.hasSuffix("/"))
    }

    @Test("A redirect is followed and each hop is its own step")
    func redirects() async throws {
        let server = try await LoopbackHTTPServer { path in
            switch path {
            case "/": LoopbackHTTPServer.response("301 Moved Permanently", headers: ["Location": "/next"])
            case "/next": LoopbackHTTPServer.response("302 Found", headers: ["Location": "/end"])
            default: LoopbackHTTPServer.response("200 OK", body: "done")
            }
        }
        defer { server.stop() }
        let steps = try await HTTPTimer.measure(URL(string: "http://127.0.0.1:\(server.port)/")!)
        #expect(steps.map(\.statusCode) == [301, 302, 200])
        #expect(steps.map(\.id) == [0, 1, 2])
        #expect(steps.last?.url.hasSuffix("/end") == true)
    }

    @Test("A redirect loop stops after the limit instead of running forever")
    func redirectLoop() async throws {
        let server = try await LoopbackHTTPServer { _ in
            LoopbackHTTPServer.response("302 Found", headers: ["Location": "/again"])
        }
        defer { server.stop() }
        let steps = try await HTTPTimer.measure(URL(string: "http://127.0.0.1:\(server.port)/")!)
        #expect(steps.count == HTTPTimer.maximumRedirects + 1)
        #expect(steps.allSatisfy { $0.statusCode == 302 })
        #expect(server.requests.count == HTTPTimer.maximumRedirects + 1)
    }

    @Test("Error statuses are results, not failures")
    func errorStatus() async throws {
        let server = try await LoopbackHTTPServer { _ in LoopbackHTTPServer.response("503 Service Unavailable") }
        defer { server.stop() }
        let steps = try await HTTPTimer.measure(URL(string: "http://127.0.0.1:\(server.port)/")!)
        #expect(steps.map(\.statusCode) == [503])
    }

    @Test("A closed port is reported as refused")
    func refused() async throws {
        // A port that was just in use and is closed again.
        let server = try await LoopbackHTTPServer { _ in "" }
        let port = server.port
        server.stop()
        try await Task.sleep(for: .milliseconds(200))
        await #expect(throws: ToolError.refused) {
            try await HTTPTimer.measure(URL(string: "http://127.0.0.1:\(port)/")!)
        }
    }

    @Test("Only the headers are read: a large body is not downloaded")
    func headersOnly() async throws {
        let body = String(repeating: "x", count: 2_000_000)
        let server = try await LoopbackHTTPServer { _ in LoopbackHTTPServer.response("200 OK", body: body) }
        defer { server.stop() }
        let started = Date()
        let steps = try await HTTPTimer.measure(URL(string: "http://127.0.0.1:\(server.port)/")!)
        #expect(steps.first?.statusCode == 200)
        #expect(Date().timeIntervalSince(started) < 5)
    }
}
