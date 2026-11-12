import Foundation
import Network
import Synchronization

/// How one address family did against a host.
public struct DualStackFamily: Sendable, Equatable {
    /// The first address of this family the system gave. `nil`: it gave none.
    public let address: String?
    /// The middle of the handshake times, `nil` if none completed.
    public let medianMilliseconds: Double?
    /// The handshake times of the attempts, `nil` for one that failed.
    public let attempts: [Double?]
    /// Why no handshake completed.
    public let error: ToolError?

    public init(address: String?, medianMilliseconds: Double?, attempts: [Double?], error: ToolError?) {
        self.address = address
        self.medianMilliseconds = medianMilliseconds
        self.attempts = attempts
        self.error = error
    }
}

public struct DualStackReport: Sendable, Equatable {
    public let ipv4: DualStackFamily
    public let ipv6: DualStackFamily
    /// The connection the system made on its own (Happy Eyeballs, RFC 8305):
    /// the address it ended up at and how long it took.
    public let systemAddress: String?
    public let systemUsedIPv6: Bool?
    public let systemMilliseconds: Double?

    public init(
        ipv4: DualStackFamily, ipv6: DualStackFamily, systemAddress: String?, systemUsedIPv6: Bool?,
        systemMilliseconds: Double?
    ) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.systemAddress = systemAddress
        self.systemUsedIPv6 = systemUsedIPv6
        self.systemMilliseconds = systemMilliseconds
    }

    /// The faster family and by how much, from the medians. `nil` unless both connected.
    public var faster: (ipv6: Bool, byMilliseconds: Double)? {
        guard let four = ipv4.medianMilliseconds, let six = ipv6.medianMilliseconds else { return nil }
        return (six < four, abs(four - six))
    }
}

/// Connects to a host over IPv4 and over IPv6, then once the way the system
/// would on its own, to see which family wins.
public enum DualStackTool {
    public static let attempts = 3

    public static func run(host: String, port: UInt16, timeoutMilliseconds: Int = 3000) async throws -> DualStackReport {
        let addresses = try await HostResolver.resolve(host)
        guard !addresses.isEmpty else { throw ToolError.cannotResolve }
        let four = addresses.first { !$0.isIPv6 }
        let six = addresses.first { $0.isIPv6 }

        // Both families side by side, a few times, so one slow handshake does not decide.
        var times4: [Double?] = []
        var times6: [Double?] = []
        var error4: ToolError?
        var error6: ToolError?
        for _ in 0..<attempts {
            async let a = handshake(four, port: port, timeout: timeoutMilliseconds)
            async let b = handshake(six, port: port, timeout: timeoutMilliseconds)
            let (r4, r6) = try await (a, b)
            if four != nil { record(r4, into: &times4, error: &error4) }
            if six != nil { record(r6, into: &times6, error: &error6) }
        }
        let system = try await systemConnection(host: host, port: port, timeout: timeoutMilliseconds)
        return DualStackReport(
            ipv4: family(four, times4, error4), ipv6: family(six, times6, error6),
            systemAddress: system?.address, systemUsedIPv6: system?.ipv6, systemMilliseconds: system?.milliseconds)
    }

    private static func handshake(_ address: ResolvedAddress?, port: UInt16, timeout: Int) async throws -> TCPProbe.Result? {
        guard let address else { return nil }
        return try await TCPProbe.once(address: address, port: port, timeoutMilliseconds: timeout)
    }

    private static func record(_ result: TCPProbe.Result?, into times: inout [Double?], error: inout ToolError?) {
        switch result {
        case .open(let milliseconds): times.append(milliseconds)
        case .closed: times.append(nil); error = .refused
        case .noResponse: times.append(nil); error = error ?? .timeout
        case .failed(let failure): times.append(nil); error = failure
        case nil: break
        }
    }

    private static func family(_ address: ResolvedAddress?, _ times: [Double?], _ error: ToolError?) -> DualStackFamily {
        let done = times.compactMap { $0 }.sorted()
        return DualStackFamily(
            address: address?.text, medianMilliseconds: done.isEmpty ? nil : done[done.count / 2], attempts: times,
            error: done.isEmpty ? error : nil)
    }

    private final class Once: Sendable {
        let state = Mutex<CheckedContinuation<(String, Bool, Double)?, Never>?>(nil)

        func set(_ continuation: CheckedContinuation<(String, Bool, Double)?, Never>) {
            state.withLock { $0 = continuation }
        }

        func finish(_ value: (String, Bool, Double)?) {
            let continuation = state.withLock { state -> CheckedContinuation<(String, Bool, Double)?, Never>? in
                defer { state = nil }
                return state
            }
            continuation?.resume(returning: value)
        }
    }

    /// A TCP connection by name, which the system races over both families.
    private static func systemConnection(
        host: String, port: UInt16, timeout: Int
    ) async throws -> (address: String, ipv6: Bool, milliseconds: Double)? {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw InputError.invalidPort }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let once = Once()
        let queue = DispatchQueue(label: "app.pingscape.dualstack")
        let started = monotonicMilliseconds()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                once.set(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let elapsed = monotonicMilliseconds() - started
                        if case .hostPort(let remote, _)? = connection.currentPath?.remoteEndpoint {
                            let text = "\(remote)".split(separator: "%").first.map(String.init) ?? "\(remote)"
                            let ipv6: Bool = if case .ipv6 = remote { true } else { false }
                            once.finish((text, ipv6, elapsed))
                        } else {
                            once.finish(nil)
                        }
                        connection.cancel()
                    case .failed, .cancelled:
                        once.finish(nil)
                        connection.cancel()
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + .milliseconds(timeout)) {
                    once.finish(nil)
                    connection.cancel()
                }
            }
        } onCancel: {
            once.finish(nil)
            connection.cancel()
        }
        try Task.checkCancellation()
        return result.map { ($0.0, $0.1, $0.2) }
    }
}
