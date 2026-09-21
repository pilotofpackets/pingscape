import Foundation

public struct TracerouteHop: Sendable, Equatable, Identifiable {
    public var id: Int { number }
    public let number: Int
    /// The router that answered, or `nil` if no probe got an answer.
    public let address: String?
    /// One entry per probe: the round trip, or `nil` for no answer.
    public let times: [Double?]

    public init(number: Int, address: String?, times: [Double?]) {
        self.number = number
        self.address = address
        self.times = times
    }
}

public enum TracerouteEvent: Sendable, Equatable {
    case started(address: String)
    case hop(TracerouteHop)
    /// The reverse DNS name of a hop, which arrives after the hop itself.
    case name(hop: Int, String)
    case finished(reachedTarget: Bool)
    case failed(ToolError)
}

public struct TracerouteSettings: Sendable, Equatable {
    public var maximumHops = 30
    public var probesPerHop = 3
    public var timeoutSeconds = 1.5
    /// Each hop address goes to the system DNS server for its name.
    public var resolveNames = true

    public init(
        maximumHops: Int = 30, probesPerHop: Int = 3, timeoutSeconds: Double = 1.5, resolveNames: Bool = true
    ) {
        self.maximumHops = maximumHops
        self.probesPerHop = probesPerHop
        self.timeoutSeconds = timeoutSeconds
        self.resolveNames = resolveNames
    }
}

/// ICMP echo with a rising hop limit. The router that cuts the limit answers
/// with "time exceeded", which names that hop.
public enum TracerouteTool {
    public static func run(
        address: ResolvedAddress, settings: TracerouteSettings = TracerouteSettings()
    ) -> AsyncStream<TracerouteEvent> {
        AsyncStream { continuation in
            let task = Task {
                guard ICMPEcho.isAvailable(ipv6: address.isIPv6) else {
                    continuation.yield(.failed(.failed("ICMP not available")))
                    continuation.finish()
                    return
                }
                continuation.yield(.started(address: address.text))
                var reached = false
                var names: [Task<Void, Never>] = []
                var sequence = 0
                hops: for number in 1...max(settings.maximumHops, 1) {
                    var times: [Double?] = []
                    var hopAddress: String?
                    var stop = false
                    for _ in 0..<max(settings.probesPerHop, 1) {
                        if Task.isCancelled { break hops }
                        sequence += 1
                        let current = UInt16(truncatingIfNeeded: sequence)
                        let timeout = Int(settings.timeoutSeconds * 1000)
                        let outcome: ICMPEcho.Outcome
                        do {
                            outcome = try await Blocking.run { cancel in
                                try ICMPEcho.send(
                                    to: address, sequence: current, ttl: Int32(number),
                                    timeoutMilliseconds: timeout, payloadSize: 32, cancel: cancel)
                            }
                        } catch {
                            break hops
                        }
                        switch outcome {
                        case .reply(let reply, let from, let milliseconds, _):
                            hopAddress = hopAddress ?? from
                            times.append(milliseconds)
                            if reply.kind == .echoReply { reached = true }
                            if reply.kind != .timeExceeded { stop = true }
                        case .timeout:
                            times.append(nil)
                        case .unsupported:
                            continuation.yield(.failed(.failed("ICMP not available")))
                            break hops
                        case .failed(let error):
                            continuation.yield(.failed(error))
                            break hops
                        }
                    }
                    continuation.yield(.hop(TracerouteHop(number: number, address: hopAddress, times: times)))
                    if settings.resolveNames, let hopAddress {
                        names.append(
                            Task {
                                if let name = await HostResolver.reverseName(of: hopAddress) {
                                    continuation.yield(.name(hop: number, name))
                                }
                            })
                    }
                    if stop { break }
                }
                if !Task.isCancelled { continuation.yield(.finished(reachedTarget: reached)) }
                for name in names { await name.value }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
