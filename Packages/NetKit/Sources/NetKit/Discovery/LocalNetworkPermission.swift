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

    /// Waits for the answer, also while the permission dialog is open.
    public static func check(timeoutSeconds: Double = 60) async -> LocalNetworkAccess {
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: "local."), using: .tcp)
        let queue = DispatchQueue(label: "app.pingscape.localnetwork")
        let box = Box()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.set(continuation)
                browser.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        // A refused browse reports `ready` first and, in the same
                        // instant, `waiting` with the policy error (seen on iOS 27,
                        // both within 3 ms). So "ready" alone proves nothing.
                        queue.asyncAfter(deadline: .now() + readyGraceSeconds) {
                            box.finish(.allowed)
                            browser.cancel()
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

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<LocalNetworkAccess, Never>?

        func set(_ continuation: CheckedContinuation<LocalNetworkAccess, Never>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func finish(_ value: LocalNetworkAccess) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }
}
