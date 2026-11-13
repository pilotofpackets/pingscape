import Foundation

/// When to ask for a rating: after the fifth tool run that ended without an
/// error, and at most once per version. iOS decides whether its dialog really
/// shows (at most three times a year, never in TestFlight builds).
///
/// Never in demo mode (screenshots, UI tests) and never inside another app
/// that embeds Pingscape: there the dialog would rate the host app.
@MainActor
enum ReviewPrompt {
    static let runsKey = "reviewPrompt.successfulRuns"
    static let askedVersionKey = "reviewPrompt.askedVersion"
    static let threshold = 5
    static let bundleIdentifier = "app.pingscape.ios"

    /// Counts a tool run that ended without an error and says whether to ask now.
    static func recordSuccessfulRun(
        defaults: UserDefaults = .standard,
        version: String = DeviceInfo.appVersion,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        isDemo: Bool = DemoLaunch.isDemo
    ) -> Bool {
        guard !isDemo, bundleIdentifier == Self.bundleIdentifier else { return false }
        let runs = defaults.integer(forKey: runsKey) + 1
        defaults.set(runs, forKey: runsKey)
        guard runs >= threshold, defaults.string(forKey: askedVersionKey) != version else { return false }
        defaults.set(version, forKey: askedVersionKey)
        return true
    }
}
