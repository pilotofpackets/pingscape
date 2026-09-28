import Foundation
import NetKit
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
    nonisolated static let placeholder = ReportFormatter.placeholder

    var isMasked = UserDefaults.standard.bool(forKey: PrivacyMask.hideByDefaultKey)

    /// Rows hidden one at a time (long press → "Hide value"), independent of
    /// `isMasked`, so a single value like the public IP can be left out of a
    /// screenshot without hiding every other row. Keyed by label and value
    /// together, since the same label can repeat on one page (several DNS
    /// servers, both a bound and an unbound "External IPv4").
    private var individuallyHidden: Set<String> = []

    /// The value, or the placeholder while values are hidden.
    func shown(_ value: String) -> String {
        isMasked ? Self.placeholder : value
    }

    func isIndividuallyHidden(label: String, value: String) -> Bool {
        individuallyHidden.contains(Self.key(label: label, value: value))
    }

    func toggleIndividuallyHidden(label: String, value: String) {
        let key = Self.key(label: label, value: value)
        if individuallyHidden.contains(key) {
            individuallyHidden.remove(key)
        } else {
            individuallyHidden.insert(key)
        }
    }

    private static func key(label: String, value: String) -> String {
        "\(label)\u{0}\(value)"
    }
}
