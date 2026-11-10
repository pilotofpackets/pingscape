import Darwin
import Foundation

/// One echo request of a path MTU search, with "don't fragment" set.
public struct PathMTUProbe: Sendable, Equatable, Identifiable {
    public enum Result: Sendable, Equatable {
        case passed(milliseconds: Double)
        /// A router on the way could not forward it unfragmented. `mtu` is what
        /// it named as the largest packet of its next link.
        case tooBig(mtu: Int?, reportedBy: String)
        /// The device did not send it: larger than the MTU it knows for the way out.
        case tooBigToSend
        /// No answer and no message, also after a second try.
        case noReply
    }

    public let id: Int
    /// The whole IP packet in bytes, headers included.
    public let packetSize: Int
    public let result: Result

    public init(id: Int, packetSize: Int, result: Result) {
        self.id = id
        self.packetSize = packetSize
        self.result = result
    }

    public var passed: Bool {
        if case .passed = result { return true }
        return false
    }
}

public enum PathMTUEvent: Sendable, Equatable {
    /// `interface` is the one the packets leave on, with its MTU, if it was found.
    case started(address: String, interface: String?, interfaceMTU: Int?)
    case probe(PathMTUProbe)
    /// `pathMTU` is the largest packet that came back. `nil`: not even a small one did.
    case finished(pathMTU: Int?)
    case failed(ToolError)
}

/// Finds the largest packet that reaches a target and comes back without
/// being fragmented: echo requests with "don't fragment", halving the range
/// between the largest that passed and the smallest that did not. A size a
/// router names in its "too big" message is tried next.
public enum PathMTUTool {
    /// The packet that must pass first: a default ping (56 bytes payload).
    static func smallPacket(ipv6: Bool) -> Int { PingSettings.headerSize(ipv6: ipv6) + 56 }

    /// The largest packet tried when the interface MTU is not known: a jumbo frame.
    static let fallbackCeiling = 9000

    public static func run(address: ResolvedAddress, timeoutSeconds: Double = 2) -> AsyncStream<PathMTUEvent> {
        AsyncStream { continuation in
            let task = Task {
                guard ICMPEcho.isAvailable(ipv6: address.isIPv6) else {
                    continuation.yield(.failed(.failed("ICMP not available")))
                    continuation.finish()
                    return
                }
                let interface = OutgoingInterface.find(for: address)
                continuation.yield(
                    .started(address: address.text, interface: interface?.name, interfaceMTU: interface?.mtu))
                let header = PingSettings.headerSize(ipv6: address.isIPv6)
                let ceiling = min(
                    interface?.mtu ?? fallbackCeiling, PingSettings.maximumPayloadSize + header)
                var search = PathMTUSearch(small: smallPacket(ipv6: address.isIPv6), ceiling: ceiling)
                var count = 0
                while let size = search.next, !Task.isCancelled {
                    count += 1
                    guard
                        let result = await probe(
                            address: address, packetSize: size, header: header, sequence: count,
                            timeout: Int(timeoutSeconds * 1000))
                    else { break }
                    if case .failure(let error) = result {
                        continuation.yield(.failed(error))
                        break
                    }
                    guard case .success(let outcome) = result else { break }
                    continuation.yield(.probe(PathMTUProbe(id: count, packetSize: size, result: outcome)))
                    search.record(size: size, result: outcome)
                }
                if !Task.isCancelled, search.next == nil { continuation.yield(.finished(pathMTU: search.largestPassed)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One size, tried twice when nothing comes back. `nil` if cancelled.
    private static func probe(
        address: ResolvedAddress, packetSize: Int, header: Int, sequence: Int, timeout: Int
    ) async -> Result<PathMTUProbe.Result, ToolError>? {
        for attempt in 0..<2 {
            let outcome: ICMPEcho.Outcome
            do {
                let sequenceNumber = UInt16(truncatingIfNeeded: sequence * 2 + attempt)
                outcome = try await Blocking.run { cancel in
                    try ICMPEcho.send(
                        to: address, sequence: sequenceNumber, timeoutMilliseconds: timeout,
                        payloadSize: packetSize - header, dontFragment: true, cancel: cancel)
                }
            } catch is CancellationError {
                return nil
            } catch {
                return .failure(.failed("\(error)"))
            }
            switch outcome {
            case .reply(let reply, let from, let milliseconds, _):
                switch reply.kind {
                case .echoReply: return .success(.passed(milliseconds: milliseconds))
                case .tooBig(let mtu): return .success(.tooBig(mtu: mtu, reportedBy: from))
                case .timeExceeded, .unreachable: return .failure(.noRoute)
                }
            case .tooBigToSend: return .success(.tooBigToSend)
            case .timeout: continue
            case .unsupported: return .failure(.failed("ICMP not available"))
            case .failed(let error): return .failure(error)
            }
        }
        return .success(.noReply)
    }
}

/// The order of sizes of a path MTU search. Pure, so it is tested without a network.
struct PathMTUSearch {
    private let small: Int
    private let ceiling: Int
    /// The largest size that came back.
    private(set) var largestPassed: Int?
    /// The smallest size that did not.
    private var smallestFailed: Int?
    /// A size a router named, to try next.
    private var hint: Int?
    private var triedSmall = false
    private var triedCeiling = false

    init(small: Int, ceiling: Int) {
        self.small = small
        self.ceiling = max(ceiling, small)
    }

    /// The next size to try, `nil` when the search is over. The largest size
    /// goes first, since most paths carry it. Then a small one, to tell a
    /// limit apart from a target that does not answer at all.
    var next: Int? {
        if !triedCeiling { return ceiling }
        if !triedSmall { return small }
        guard let low = largestPassed, let high = smallestFailed, high - low > 1 else { return nil }
        if let hint, hint > low, hint < high { return hint }
        return (low + high) / 2
    }

    mutating func record(size: Int, result: PathMTUProbe.Result) {
        if size == ceiling { triedCeiling = true }
        if size == small { triedSmall = true }
        if size == hint { hint = nil }
        if case .passed = result {
            largestPassed = max(largestPassed ?? size, size)
            // The full size passed: nothing to search.
            if size == ceiling { triedSmall = true; smallestFailed = size + 1 }
            return
        }
        smallestFailed = min(smallestFailed ?? size, size)
        // Nothing larger than the named MTU gets over that link.
        if case .tooBig(let mtu?, _) = result, mtu < size {
            smallestFailed = min(smallestFailed ?? mtu + 1, mtu + 1)
            hint = mtu
        }
        if size == small { largestPassed = nil; smallestFailed = nil }
    }
}

/// The interface the system would send a packet to an address on.
enum OutgoingInterface {
    /// Connects a UDP socket, which sends nothing, and reads the local address
    /// the system picked. The interface holding that address is the one.
    static func find(for address: ResolvedAddress) -> NetworkInterface? {
        guard let socket = try? POSIXSocket(family: address.family, type: SOCK_DGRAM) else { return nil }
        let status = address.withSockaddr(port: 9) { sa, length in Darwin.connect(socket.fd, sa, length) }
        guard status == 0 else { return nil }
        var local = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let named = withUnsafeMutablePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket.fd, $0, &length) }
        }
        guard named == 0 else { return nil }
        let bytes = withUnsafeBytes(of: &local) { Array($0.prefix(Int(length))) }
        guard let ip = ResolvedAddress.text(ofSockaddr: bytes) else { return nil }
        return InterfaceCollector.collect().first { interface in
            interface.addresses.contains { $0.ip == ip }
        }
    }
}
