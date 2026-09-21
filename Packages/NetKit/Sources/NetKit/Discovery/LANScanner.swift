import Foundation

public enum LANScanMode: String, Sendable, Equatable {
    /// Ping every address and listen for Bonjour.
    case quick
    /// Also try a few TCP ports on addresses that did not answer the ping, and
    /// list the open ports of every device.
    case thorough
}

/// Finds the devices on the local IPv4 network.
///
/// The sweep pings every address of the network. Whoever answers is on the
/// list at once. What Bonjour and a reverse lookup add is attached to the
/// device by its address. Nothing is guessed: a device that answers only a
/// ping is listed as such.
public enum LANScanner {
    /// At most this many addresses are searched. Larger networks are cut down
    /// to the block that holds this device, and the result says so.
    public static let addressLimit = 1024
    public static let pingTimeoutMilliseconds = 600
    public static let pingConcurrency = 48
    /// The ports of the thorough search.
    public static let probePorts: [UInt16] = [80, 443, 62078, 445]

    /// The addresses to search: the whole network if it is small enough, else
    /// the aligned block of `limit` addresses around `ip`. This device is left out.
    public static func addresses(in range: IPv4Range, around ip: String, limit: Int = addressLimit) -> (addresses: [String], capped: Bool) {
        let hosts = range.hosts(limit: Int.max)
        guard range.hostCount > limit, let own = IPv4.toInt(ip) else {
            return (hosts.filter { $0 != ip }, false)
        }
        let size = UInt32(limit)
        let start = own / size * size
        let block = (0..<size).map { IPv4.toString(start + $0) }.filter { candidate in
            guard let value = IPv4.toInt(candidate) else { return false }
            // Neither the network address nor the broadcast address of the whole network.
            return candidate != ip && value > range.network && candidate != range.broadcast
        }
        return (block, true)
    }

    public static func run(
        range: IPv4Range, thisDevice: String, mode: LANScanMode = .quick
    ) -> AsyncStream<LANEvent> {
        AsyncStream { continuation in
            let task = Task {
                let (addresses, capped) = addresses(in: range, around: thisDevice)
                continuation.yield(.started(network: range.description, total: addresses.count, capped: capped))

                await withTaskGroup(of: Void.self) { group in
                    // Bonjour runs beside the sweep and for a few seconds after it.
                    group.addTask {
                        for await finding in BonjourBrowser.browse() {
                            // Only devices of this network: a service can also resolve to
                            // the loopback address or to another interface.
                            guard let value = IPv4.toInt(finding.ip), value > range.network,
                                IPv4Range(ip: finding.ip, prefix: range.prefix)?.network == range.network
                            else { continue }
                            continuation.yield(.service(ip: finding.ip, finding.service))
                        }
                    }

                    // The sweep, then the thorough probes, then the names.
                    group.addTask {
                        let responders = await sweep(addresses, continuation: continuation)
                        if Task.isCancelled { return }
                        var found = responders
                        if mode == .thorough {
                            found = await probe(addresses, responders: responders, continuation: continuation)
                        }
                        await lookUpNames(found, continuation: continuation)
                    }
                    await group.waitForAll()
                }
                if !Task.isCancelled { continuation.yield(.finished) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Pings all addresses. Returns the ones that answered.
    private static func sweep(
        _ addresses: [String], continuation: AsyncStream<LANEvent>.Continuation
    ) async -> [String] {
        do {
            return try await Blocking.run { cancel -> [String] in
                var found: [String] = []
                try ICMPSweep.run(
                    addresses: addresses, timeoutMilliseconds: pingTimeoutMilliseconds,
                    concurrency: pingConcurrency, cancel: cancel,
                    onReply: { address, milliseconds in
                        found.append(address)
                        continuation.yield(.ping(ip: address, milliseconds: milliseconds))
                    },
                    onProgress: { done, total in continuation.yield(.progress(done: done, total: total)) })
                return found
            }
        } catch let error as ToolError {
            continuation.yield(.failed(error))
            return []
        } catch {
            return []
        }
    }

    /// TCP probes for addresses that did not answer the ping, and the open
    /// ports of every device. A refused connection also proves the device is there.
    private static func probe(
        _ addresses: [String], responders: [String], continuation: AsyncStream<LANEvent>.Continuation
    ) async -> [String] {
        let silent = addresses.filter { !responders.contains($0) }
        let targets = (responders + silent).flatMap { ip -> [(String, UInt16)] in probePorts.map { (ip, $0) } }
        var builtProbes: [TCPProbe.Target] = []
        var builtOwners: [Int: (ip: String, port: UInt16)] = [:]
        for (index, target) in targets.enumerated() {
            guard let address = ResolvedAddress(literal: target.0) else { continue }
            builtProbes.append(TCPProbe.Target(id: index, address: address, port: target.1))
            builtOwners[index] = target
        }
        let probes = builtProbes
        let owners = builtOwners
        let outcome = try? await Blocking.run { cancel -> (open: [String: [Int]], alive: Set<String>) in
            var open: [String: [Int]] = [:]
            var alive = Set<String>()
            TCPProbe.run(targets: probes, timeoutMilliseconds: 500, concurrency: 64, cancel: cancel) { id, result in
                guard let owner = owners[id] else { return }
                switch result {
                case .open:
                    open[owner.ip, default: []].append(Int(owner.port))
                    alive.insert(owner.ip)
                case .closed:
                    alive.insert(owner.ip)
                case .noResponse, .failed:
                    break
                }
            }
            return (open, alive)
        }
        guard let outcome else { return responders }
        for ip in silent where outcome.alive.contains(ip) { continuation.yield(.reachable(ip: ip)) }
        for (ip, ports) in outcome.open { continuation.yield(.ports(ip: ip, ports)) }
        return responders + silent.filter { outcome.alive.contains($0) }
    }

    /// Reverse DNS names, a few at a time.
    private static func lookUpNames(_ addresses: [String], continuation: AsyncStream<LANEvent>.Continuation) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = addresses.makeIterator()
            var running = 0
            while running < 8, let ip = iterator.next() {
                running += 1
                group.addTask { await name(ip, continuation) }
            }
            while await group.next() != nil {
                if let ip = iterator.next() {
                    group.addTask { await name(ip, continuation) }
                }
            }
        }
    }

    private static func name(_ ip: String, _ continuation: AsyncStream<LANEvent>.Continuation) async {
        if let name = await HostResolver.reverseName(of: ip) {
            continuation.yield(.hostname(ip: ip, name: name))
        }
    }
}
