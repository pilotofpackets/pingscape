import Observation

/// Hides sensitive values (addresses, network names) for screenshots.
@MainActor
@Observable
final class PrivacyMask {
    var isMasked = false
}
