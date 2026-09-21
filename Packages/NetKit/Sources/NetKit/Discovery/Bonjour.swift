import Foundation
import Network

/// A Bonjour service on a device, with the address it resolved to.
public struct BonjourFinding: Sendable, Equatable {
    public let ip: String
    public let service: LANService
}

/// Looks for Bonjour (mDNS) services of a curated list of types.
///
/// Browsing all service types (`_services._dns-sd._udp`) needs Apple's
/// multicast entitlement, so the list stays short and mirrors
/// `NSBonjourServices` in the app's Info.plist. A type missing there is
/// silently not delivered by the system.
public enum BonjourBrowser {
    /// Keep in sync with `NSBonjourServices` in `project.yml`.
    public static let serviceTypes = [
        "_http._tcp", "_https._tcp", "_airplay._tcp", "_raop._tcp", "_hap._tcp", "_googlecast._tcp",
        "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_smb._tcp", "_afpovertcp._tcp", "_ssh._tcp",
        "_sftp-ssh._tcp", "_companion-link._tcp", "_device-info._tcp", "_workstation._tcp", "_matter._tcp",
        "_meshcop._udp", "_spotify-connect._tcp", "_sonos._tcp",
    ]

    /// Findings until the stream is cancelled or `duration` has passed.
    public static func browse(
        types: [String] = serviceTypes, duration: Duration = .seconds(6)
    ) -> AsyncStream<BonjourFinding> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "app.pingscape.bonjour")
            let resolver = Resolver(continuation: continuation)
            let browsers = types.map { type -> NWBrowser in
                let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: .tcp)
                browser.browseResultsChangedHandler = { results, _ in
                    for result in results { resolver.resolve(result, type: type) }
                }
                browser.start(queue: queue)
                return browser
            }
            let timer = Task {
                try? await Task.sleep(for: duration)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                timer.cancel()
                browsers.forEach { $0.cancel() }
                resolver.cancelAll()
            }
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
