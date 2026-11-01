import Foundation
import Network

public enum LocalNetworkAccess: String, Sendable, Equatable {
    case allowed
    case denied
    /// The system did not answer in time.
    case unknown
}

/// Finds out whether the app may use the local network.
///
/// iOS has no call that reads the permission. The first Bonjour browse asks
/// the user, and a browse without permission ends in the "waiting" state with
/// a DNS policy error (after a short "ready"). This starts one browse and reads
/// which of the two happens.
/// A browse of a type listed in `NSBonjourServices` is what makes iOS ask.
public enum LocalNetworkPermission {
    /// `kDNSServiceErr_PolicyDenied`
    static let policyDenied = -65570

    /// How long a browse must stay without the policy error after `ready`.
    static let readyGraceSeconds = 0.5

    /// How often a send to the probe address is tried while the answer is open.
    static let probeIntervalSeconds = 0.25

    /// Waits for the answer, also while the permission dialog is open.
    ///
    /// `probe` is an address on the local network that is not the router.
    /// While the dialog is still open the browse already reports `ready` (seen
    /// on iOS 27, 2026-11-01, 21 ms after the start), but every send into the
    /// local network fails with `EHOSTUNREACH` until the user allows it. The
    /// first search after a fresh install took that `ready` for an answer, and
    /// its sweep found nothing but the router. With a probe, "allowed" waits
    /// until a send to it goes through.
    public static func check(timeoutSeconds: Double = 60, probe: String? = nil) async -> LocalNetworkAccess {
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: "local."), using: .tcp)
        let queue = DispatchQueue(label: "app.pingscape.localnetwork")
        let box = Box()
        let target = probe.flatMap(ResolvedAddress.init(literal:))
        // Tries the probe until a send goes through or the answer is in.
        @Sendable func tryProbe(_ target: ResolvedAddress) {
            guard !box.isFinished else { return }
            if canSend(to: target) {
                box.finish(.allowed)
                browser.cancel()
            } else {
                queue.asyncAfter(deadline: .now() + probeIntervalSeconds) { tryProbe(target) }
            }
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.set(continuation)
                browser.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        // A refused browse reports `ready` first and, in the same
                        // instant, `waiting` with the policy error (seen on iOS 27,
                        // both within 3 ms). So "ready" alone proves nothing.
                        guard box.startWaitingAfterReady() else { break }
                        queue.asyncAfter(deadline: .now() + readyGraceSeconds) {
                            if let target {
                                tryProbe(target)
                            } else {
                                box.finish(.allowed)
                                browser.cancel()
                            }
                        }
                    case .waiting(let error):
                        if case .dns(let code) = error, Int(code) == policyDenied {
                            box.finish(.denied)
                            browser.cancel()
                        }
                    case .failed:
                        box.finish(.unknown)
                        browser.cancel()
                    default:
                        break
                    }
                }
                browser.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                    box.finish(.unknown)
                    browser.cancel()
                }
            }
        } onCancel: {
            box.finish(.unknown)
            browser.cancel()
        }
    }

    /// Whether iOS lets a datagram through to `target`. Only `EHOSTUNREACH`
    /// means "not allowed (yet)"; any other outcome is not about the permission.
    private static func canSend(to target: ResolvedAddress) -> Bool {
        guard let socket = try? POSIXSocket(family: target.family, type: SOCK_DGRAM) else { return true }
        let byte: [UInt8] = [0]
        // Port 9 is "discard": nothing on the other side reacts to the byte.
        let sent = byte.withUnsafeBytes { raw in
            target.withSockaddr(port: 9) { sa, length in Darwin.sendto(socket.fd, raw.baseAddress, byte.count, 0, sa, length) }
        }
        return sent >= 0 || errno != EHOSTUNREACH
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<LocalNetworkAccess, Never>?
        private var finished = false
        private var waitingAfterReady = false

        var isFinished: Bool {
            lock.lock()
            defer { lock.unlock() }
            return finished
        }

        func set(_ continuation: CheckedContinuation<LocalNetworkAccess, Never>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        /// True only the first time: `ready` can come more than once.
        func startWaitingAfterReady() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if waitingAfterReady { return false }
            waitingAfterReady = true
            return true
        }

        func finish(_ value: LocalNetworkAccess) {
            lock.lock()
            let pending = continuation
            continuation = nil
            finished = true
            lock.unlock()
            pending?.resume(returning: value)
        }
    }
}
