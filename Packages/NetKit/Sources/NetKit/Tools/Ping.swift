import Foundation

public enum PingMethod: Sendable, Equatable {
    case icmp
    /// ICMP is not available, so the round trip is a TCP handshake. The app
    /// says so next to the result.
    case tcp(port: UInt16)
}

public struct PingSettings: Sendable, Equatable {
    /// Payload bytes, 0 to 1400.
    public var payloadSize = 56
    public var intervalSeconds = 1.0
    public var timeoutSeconds = 2.0

    public init(payloadSize: Int = 56, intervalSeconds: Double = 1.0, timeoutSeconds: Double = 2.0) {
        self.payloadSize = payloadSize
        self.intervalSeconds = intervalSeconds
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum PingEvent: Sendable, Equatable {
    case started(address: String, method: PingMethod)
    case reply(sequence: Int, bytes: Int?, milliseconds: Double, ttl: Int?)
    /// Nothing came back in the time limit.
    case noReply(sequence: Int)
    /// The attempt itself failed (no route, not permitted). Counts as lost.
    case failed(sequence: Int, ToolError)
}

/// Round-trip statistics over the replies of a run.
public struct PingStatistics: Sendable, Equatable {
    public private(set) var sent = 0
    public private(set) var received = 0
    public private(set) var minimum: Double?
    public private(set) var maximum: Double?
    private var total = 0.0
    private var previous: Double?
    private var differenceTotal = 0.0
    private var differenceCount = 0

    public init() {}

    public mutating func recordReply(milliseconds: Double) {
        sent += 1
        received += 1
        total += milliseconds
        minimum = min(minimum ?? milliseconds, milliseconds)
        maximum = max(maximum ?? milliseconds, milliseconds)
        if let previous {
            differenceTotal += abs(milliseconds - previous)
            differenceCount += 1
        }
        previous = milliseconds
    }

    public mutating func recordLoss() {
        sent += 1
    }

    public var lostPercent: Double {
        sent == 0 ? 0 : Double(sent - received) / Double(sent) * 100
    }

    public var average: Double? {
        received == 0 ? nil : total / Double(received)
    }

    /// The mean of the absolute differences of consecutive round trips. The
    /// Live tab uses the same definition.
    public var jitter: Double? {
        differenceCount == 0 ? nil : differenceTotal / Double(differenceCount)
    }
}

public enum PingTool {
    /// The port of the TCP fallback.
    public static let fallbackPort: UInt16 = 443

    /// Pings until the stream is cancelled. The first event names the address
    /// and the method, so a TCP ping never passes for ICMP.
    public static func run(address: ResolvedAddress, settings: PingSettings = PingSettings()) -> AsyncStream<PingEvent> {
        AsyncStream { continuation in
            let task = Task {
                var method: PingMethod = ICMPEcho.isAvailable(ipv6: address.isIPv6) ? .icmp : .tcp(port: fallbackPort)
                continuation.yield(.started(address: address.text, method: method))
                var sequence = 0
                while !Task.isCancelled {
                    sequence += 1
                    let started = monotonicMilliseconds()
                    let event = await attempt(
                        address: address, sequence: sequence, method: &method, settings: settings,
                        announce: { continuation.yield($0) })
                    guard let event else { break }
                    continuation.yield(event)
                    let spent = (monotonicMilliseconds() - started) / 1000
                    do {
                        try await Task.sleep(for: .seconds(max(settings.intervalSeconds - spent, 0)))
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One attempt. `nil` if the task was cancelled.
    private static func attempt(
        address: ResolvedAddress, sequence: Int, method: inout PingMethod, settings: PingSettings,
        announce: (PingEvent) -> Void
    ) async -> PingEvent? {
        let timeout = Int(settings.timeoutSeconds * 1000)
        do {
            if case .tcp(let port) = method {
                return tcpEvent(
                    try await TCPProbe.once(address: address, port: port, timeoutMilliseconds: timeout),
                    sequence: sequence)
            }
            let payload = settings.payloadSize
            let outcome = try await Blocking.run { cancel in
                try ICMPEcho.send(
                    to: address, sequence: UInt16(truncatingIfNeeded: sequence), timeoutMilliseconds: timeout,
                    payloadSize: payload, cancel: cancel)
            }
            switch outcome {
            case .reply(let reply, _, let milliseconds, let bytes):
                switch reply.kind {
                case .echoReply:
                    return .reply(
                        sequence: sequence, bytes: bytes, milliseconds: milliseconds,
                        ttl: reply.ttl.map(Int.init))
                case .timeExceeded, .unreachable:
                    return .failed(sequence: sequence, .noRoute)
                }
            case .timeout:
                return .noReply(sequence: sequence)
            case .failed(let error):
                return .failed(sequence: sequence, error)
            case .unsupported:
                let port = fallbackPort
                method = .tcp(port: port)
                announce(.started(address: address.text, method: method))
                return tcpEvent(
                    try await TCPProbe.once(address: address, port: port, timeoutMilliseconds: timeout),
                    sequence: sequence)
            }
        } catch is CancellationError {
            return nil
        } catch {
            return .failed(sequence: sequence, .failed("\(error)"))
        }
    }

    private static func tcpEvent(_ result: TCPProbe.Result, sequence: Int) -> PingEvent {
        switch result {
        case .open(let milliseconds):
            .reply(sequence: sequence, bytes: nil, milliseconds: milliseconds, ttl: nil)
        // A refusal still crossed the network, but it is no handshake.
        case .closed: .failed(sequence: sequence, .refused)
        case .noResponse: .noReply(sequence: sequence)
        case .failed(let error): .failed(sequence: sequence, error)
        }
    }
}
