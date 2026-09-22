import Foundation
import Network

/// Reads the reachability state (`NWPath`) once.
public enum PathCollector {
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<PathSummary?, Never>?

        init(_ continuation: CheckedContinuation<PathSummary?, Never>) {
            self.continuation = continuation
        }

        func resume(_ value: PathSummary?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }

    /// The current path, or `nil` if the system did not answer in time.
    public static func current(timeoutSeconds: Double = 1.5) async -> PathSummary? {
        async let cellular = cellularInterfaceName(timeoutSeconds: timeoutSeconds)
        guard let summary = await currentPath(timeoutSeconds: timeoutSeconds) else { return nil }
        return summary.with(cellularInterface: await cellular)
    }

    /// The interface a path monitor for cellular only names, or `nil` without cellular.
    static func cellularInterfaceName(timeoutSeconds: Double) async -> String? {
        await withCheckedContinuation { continuation in
            let once = OnceName(continuation)
            let monitor = NWPathMonitor(requiredInterfaceType: .cellular)
            monitor.pathUpdateHandler = { path in
                once.resume(path.status == .satisfied ? path.availableInterfaces.first?.name : nil)
                monitor.cancel()
            }
            let queue = DispatchQueue(label: "app.pingscape.path.cellular")
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                once.resume(nil)
                monitor.cancel()
            }
        }
    }

    private final class OnceName: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String?, Never>?

        init(_ continuation: CheckedContinuation<String?, Never>) {
            self.continuation = continuation
        }

        func resume(_ value: String?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }

    private static func currentPath(timeoutSeconds: Double) async -> PathSummary? {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                once.resume(
                    PathSummary(
                        isOnline: path.status == .satisfied,
                        supportsIPv4: path.supportsIPv4,
                        supportsIPv6: path.supportsIPv6,
                        supportsDNS: path.supportsDNS,
                        isExpensive: path.isExpensive,
                        isConstrained: path.isConstrained,
                        gateways: path.gateways.compactMap(gatewayText),
                        unsatisfiedReason: path.status == .satisfied ? nil : reason(path.unsatisfiedReason)))
                monitor.cancel()
            }
            let queue = DispatchQueue(label: "app.pingscape.path")
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                once.resume(nil)
                monitor.cancel()
            }
        }
    }

    private static func gatewayText(_ endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        return "\(host)".split(separator: "%").first.map(String.init)
    }

    private static func reason(_ reason: NWPath.UnsatisfiedReason) -> UnsatisfiedReason? {
        switch reason {
        case .notAvailable: .notAvailable
        case .cellularDenied: .cellularDenied
        case .wifiDenied: .wifiDenied
        case .localNetworkDenied: .localNetworkDenied
        case .vpnInactive: .vpnInactive
        @unknown default: nil
        }
    }

    /// The interfaces `NWPath` currently knows about, to bind a request to one
    /// of them by name (Wi-Fi's `en0`, cellular's `pdp_ip0`), bypassing a VPN
    /// that otherwise carries the traffic of a request made the normal way.
    public static func availableInterfaces(timeoutSeconds: Double = 1.5) async -> [NWInterface] {
        await withCheckedContinuation { continuation in
            let once = OnceInterfaces(continuation)
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                once.resume(path.status == .satisfied ? path.availableInterfaces : [])
                monitor.cancel()
            }
            let queue = DispatchQueue(label: "app.pingscape.path.interfaces")
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                once.resume([])
                monitor.cancel()
            }
        }
    }

    private final class OnceInterfaces: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[NWInterface], Never>?

        init(_ continuation: CheckedContinuation<[NWInterface], Never>) {
            self.continuation = continuation
        }

        func resume(_ value: [NWInterface]) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }

    /// A stream that yields whenever the network path changes.
    public static func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { _ in continuation.yield() }
            monitor.start(queue: DispatchQueue(label: "app.pingscape.path.changes"))
            continuation.onTermination = { _ in monitor.cancel() }
        }
    }
}
