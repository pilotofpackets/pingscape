import Foundation
import Observation

/// Hides sensitive values (addresses, network names) for screenshots.
@MainActor
@Observable
final class PrivacyMask {
    /// The setting "Hide values by default" (About). It only decides the state
    /// at launch. Toggling the eye in the toolbar does not change it.
    nonisolated static let hideByDefaultKey = "hideValuesByDefault"

    /// What stands in for a hidden value. A fixed length, so the length of an
    /// address does not give away whether it is IPv4 or IPv6.
    nonisolated static let placeholder = "•••••••"

    var isMasked = UserDefaults.standard.bool(forKey: PrivacyMask.hideByDefaultKey)

    /// The value, or the placeholder while values are hidden.
    func shown(_ value: String) -> String {
        isMasked ? Self.placeholder : value
    }
}
