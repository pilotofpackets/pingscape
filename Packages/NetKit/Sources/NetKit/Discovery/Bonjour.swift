import Foundation
import Network

/// A Bonjour service on a device, with the address it resolved to.
public struct BonjourFinding: Sendable, Equatable {
    public let ip: String
    public let service: LANService
}

/// Looks for Bonjour (mDNS) services: first a curated list of types that need
/// no special permission, then, with Apple's multicast entitlement, every
/// other type the network actually announces.
public enum BonjourBrowser {
    /// Keep in sync with `NSBonjourServices` in `project.yml`. Browsed even
    /// without the multicast entitlement, since they are declared there.
    public static let serviceTypes = [
        "_http._tcp", "_https._tcp", "_airplay._tcp", "_raop._tcp", "_hap._tcp", "_googlecast._tcp",
        "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_smb._tcp", "_afpovertcp._tcp", "_ssh._tcp",
        "_sftp-ssh._tcp", "_companion-link._tcp", "_device-info._tcp", "_workstation._tcp", "_matter._tcp",
        "_meshcop._udp", "_spotify-connect._tcp", "_sonos._tcp",
    ]

    /// Browsing this special type returns, as its results' names, every
    /// service type the network announces (the DNS-SD meta-query). Needs the
    /// multicast entitlement; without it the browse silently finds nothing,
    /// and discovery stays with `serviceTypes` above.
    private static let metaQueryType = "_services._dns-sd._udp"

    /// Findings until the stream is cancelled or `duration` has passed. Types
    /// beyond `types` that the meta-query turns up are browsed too, as they
    /// are found, and so may keep delivering results until near the end.
    public static func browse(
        types: [String] = serviceTypes, duration: Duration = .seconds(6)
    ) -> AsyncStream<BonjourFinding> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "app.pingscape.bonjour")
            let resolver = Resolver(continuation: continuation)
            let tracker = BrowserTracker(startedTypes: Set(types))

            @Sendable func startBrowser(for type: String) {
                let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: .tcp)
                browser.browseResultsChangedHandler = { results, _ in
                    for result in results { resolver.resolve(result, type: type) }
                }
                browser.start(queue: queue)
                tracker.add(browser)
            }

            types.forEach(startBrowser)
            let metaBrowser = NWBrowser(for: .bonjour(type: metaQueryType, domain: "local."), using: .tcp)
            metaBrowser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    // For the meta-query, the system puts the discovered type
                    // itself (e.g. "_http._tcp") where an ordinary browse
                    // puts the instance name, in the first position.
                    guard case .service(let type, _, _, _) = result.endpoint, tracker.markStarted(type) else { continue }
                    startBrowser(for: type)
                }
            }
            metaBrowser.start(queue: queue)
            tracker.add(metaBrowser)

            let timer = Task {
                try? await Task.sleep(for: duration)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                timer.cancel()
                tracker.cancelAll()
                resolver.cancelAll()
            }
        }
    }

    /// The browsers started so far and the types already covered, safe to
    /// touch from a browser's own result handler and from cancellation.
    private final class BrowserTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var browsers: [NWBrowser] = []
        private var startedTypes: Set<String>

        init(startedTypes: Set<String>) { self.startedTypes = startedTypes }

        func add(_ browser: NWBrowser) {
            lock.lock()
            browsers.append(browser)
            lock.unlock()
        }

        /// Whether `type` had not been started yet, marking it as started either way.
        func markStarted(_ type: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return startedTypes.insert(type).inserted
        }

        func cancelAll() {
            lock.lock()
            let all = browsers
            browsers = []
            lock.unlock()
            all.forEach { $0.cancel() }
        }
    }

    /// Turns a browse result into an IPv4 address. Resolving uses a UDP
    /// connection to the service endpoint: the system looks the service up over
    /// mDNS, and nothing is sent to the device.
    private final class Resolver: @unchecked Sendable {
        private let lock = NSLock()
        private var seen = Set<String>()
        private var connections: [NWConnection] = []
        private let continuation: AsyncStream<BonjourFinding>.Continuation
        private let queue = DispatchQueue(label: "app.pingscape.bonjour.resolve")

        init(continuation: AsyncStream<BonjourFinding>.Continuation) {
            self.continuation = continuation
        }

        func cancelAll() {
            lock.lock()
            let all = connections
            connections = []
            lock.unlock()
            all.forEach { $0.cancel() }
        }

        func resolve(_ result: NWBrowser.Result, type: String) {
            guard case .service(let name, _, _, _) = result.endpoint else { return }
            let key = type + "|" + name
            lock.lock()
            let isNew = seen.insert(key).inserted
            lock.unlock()
            guard isNew else { return }

            var readTXT: [String: String] = [:]
            if case .bonjour(let record) = result.metadata {
                for (key, value) in record.dictionary { readTXT[key] = value }
            }
            let txt = readTXT

            let parameters = NWParameters.udp
            (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
            let connection = NWConnection(to: result.endpoint, using: parameters)
            lock.lock()
            connections.append(connection)
            lock.unlock()

            let done = OnceFlag()
            connection.stateUpdateHandler = { [continuation] state in
                switch state {
                case .ready:
                    if done.claim(), case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint,
                        case .ipv4(let address) = host
                    {
                        let ip = "\(address)".split(separator: "%").first.map(String.init) ?? "\(address)"
                        continuation.yield(
                            BonjourFinding(
                                ip: ip,
                                service: LANService(type: type, name: name, port: Int(port.rawValue), txt: txt)))
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    _ = done.claim()
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: queue)
            // A service that does not resolve in a few seconds is dropped.
            queue.asyncAfter(deadline: .now() + 4) { connection.cancel() }
        }
    }

    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }
}
