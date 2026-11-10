import Foundation

/// One hop of a continuous traceroute, over all rounds so far.
public struct MTRHop: Sendable, Equatable, Identifiable {
    public var id: Int { number }
    public let number: Int
    /// Every address that answered for this hop, in the order first seen.
    /// More than one when the routers share the load (ECMP).
    public internal(set) var addresses: [String] = []
    public internal(set) var statistics = PingStatistics()
    /// The round trip of the latest round, `nil` if it got no answer.
    public internal(set) var last: Double?

    public init(number: Int, addresses: [String] = [], statistics: PingStatistics = PingStatistics(), last: Double? = nil) {
        self.number = number
        self.addresses = addresses
        self.statistics = statistics
        self.last = last
    }

    public mutating func record(_ answer: (address: String, milliseconds: Double)?) {
        guard let answer else {
            statistics.recordLoss()
            last = nil
            return
        }
        statistics.recordReply(milliseconds: answer.milliseconds)
        last = answer.milliseconds
        if !addresses.contains(answer.address) { addresses.append(answer.address) }
    }
}

public enum MTREvent: Sendable, Equatable {
    case started(address: String)
    /// The hops after a round. `reachedTarget` once the target itself answered.
    case round(number: Int, hops: [MTRHop], reachedTarget: Bool)
    /// The reverse DNS name of an address, once.
    case name(address: String, String)
    case failed(ToolError)
}

/// A traceroute that keeps going, like `mtr`: each round sends one echo
/// request per hop, all at once, and adds the answers to the statistics of
/// that hop. The first round finds how far the target is.
public enum MTRTool {
    public static func run(
        address: ResolvedAddress, settings: TracerouteSettings = TracerouteSettings(), intervalSeconds: Double = 1
    ) -> AsyncStream<MTREvent> {
        AsyncStream { continuation in
            let task = Task {
                guard ICMPEcho.isAvailable(ipv6: address.isIPv6) else {
                    continuation.yield(.failed(.failed("ICMP not available")))
                    continuation.finish()
                    return
                }
                continuation.yield(.started(address: address.text))
                let timeout = Int(settings.timeoutSeconds * 1000)
                var limit = max(settings.maximumHops, 1)
                var hops: [MTRHop] = []
                var reached = false
                var named: Set<String> = []
                var names: [Task<Void, Never>] = []
                var round = 0
                while !Task.isCancelled {
                    round += 1
                    let started = monotonicMilliseconds()
                    let answers = await probeRound(
                        address: address, hops: limit, round: round, timeout: timeout)
                    if Task.isCancelled { break }
                    if case .failure(let error) = answers {
                        continuation.yield(.failed(error))
                        break
                    }
                    guard case .success(let results) = answers else { break }
                    // The target's own answer ends the path. Later hops are
                    // the target answering again, not new routers.
                    if let target = results.firstIndex(where: { $0?.isTarget == true }) {
                        reached = true
                        limit = min(limit, target + 1)
                    }
                    while hops.count < limit { hops.append(MTRHop(number: hops.count + 1)) }
                    if hops.count > limit { hops.removeLast(hops.count - limit) }
                    for index in hops.indices {
                        let result = index < results.count ? results[index] : nil
                        hops[index].record(result.map { ($0.address, $0.milliseconds) })
                        if settings.resolveNames, let found = result?.address, !named.contains(found) {
                            named.insert(found)
                            names.append(
                                Task {
                                    if let name = await HostResolver.reverseName(of: found) {
                                        continuation.yield(.name(address: found, name))
                                    }
                                })
                        }
                    }
                    continuation.yield(.round(number: round, hops: hops, reachedTarget: reached))
                    let spent = (monotonicMilliseconds() - started) / 1000
                    do {
                        try await Task.sleep(for: .seconds(max(intervalSeconds - spent, 0)))
                    } catch {
                        break
                    }
                }
                for name in names { name.cancel() }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct Answer: Sendable {
        let address: String
        let milliseconds: Double
        let isTarget: Bool
    }

    /// One echo request per hop limit 1 through `hops`, in parallel. Each
    /// carries its own sequence number, which is how the "time exceeded"
    /// messages are told apart.
    private static func probeRound(
        address: ResolvedAddress, hops: Int, round: Int, timeout: Int
    ) async -> Result<[Answer?], ToolError> {
        await withTaskGroup(of: (Int, Result<Answer?, ToolError>).self) { group in
            for hop in 1...hops {
                let sequence = UInt16(truncatingIfNeeded: round * 64 + hop)
                group.addTask {
                    do {
                        let outcome = try await Blocking.run { cancel in
                            try ICMPEcho.send(
                                to: address, sequence: sequence, ttl: Int32(hop), timeoutMilliseconds: timeout,
                                payloadSize: 32, cancel: cancel)
                        }
                        switch outcome {
                        case .reply(let reply, let from, let milliseconds, _):
                            return (hop, .success(Answer(
                                address: from, milliseconds: milliseconds, isTarget: reply.kind == .echoReply)))
                        case .timeout, .tooBigToSend:
                            return (hop, .success(nil))
                        case .unsupported:
                            return (hop, .failure(.failed("ICMP not available")))
                        case .failed(let error):
                            return (hop, .failure(error))
                        }
                    } catch {
                        return (hop, .success(nil))
                    }
                }
            }
            var answers = [Answer?](repeating: nil, count: hops)
            var failure: ToolError?
            for await (hop, result) in group {
                switch result {
                case .success(let answer): answers[hop - 1] = answer
                case .failure(let error): failure = failure ?? error
                }
            }
            // A failed send for every hop (no route, not allowed) ends the run.
            if let failure, answers.allSatisfy({ $0 == nil }) { return .failure(failure) }
            return .success(answers)
        }
    }
}
