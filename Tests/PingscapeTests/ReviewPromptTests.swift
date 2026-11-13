import Foundation
import Testing

@testable import Pingscape

@MainActor
@Suite("Asking for a rating")
struct ReviewPromptTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ReviewPromptTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func run(_ defaults: UserDefaults, version: String = "1.1.0", bundle: String? = ReviewPrompt.bundleIdentifier,
                     demo: Bool = false) -> Bool {
        ReviewPrompt.recordSuccessfulRun(defaults: defaults, version: version, bundleIdentifier: bundle, isDemo: demo)
    }

    @Test("Asks after the fifth good run, once per version")
    func fifthRunOncePerVersion() {
        let defaults = freshDefaults()
        let answers = (1...8).map { _ in run(defaults) }
        #expect(answers == [false, false, false, false, true, false, false, false])
        // The next version may ask once more, right at its first good run.
        #expect(run(defaults, version: "1.2.0"))
        #expect(!run(defaults, version: "1.2.0"))
    }

    @Test("Never in demo mode")
    func notInDemo() {
        let defaults = freshDefaults()
        for _ in 1...10 { #expect(!run(defaults, demo: true)) }
        #expect(defaults.integer(forKey: ReviewPrompt.runsKey) == 0)
    }

    @Test("Never inside an app that embeds Pingscape")
    func notEmbedded() {
        let defaults = freshDefaults()
        for _ in 1...10 { #expect(!run(defaults, bundle: "com.example.host")) }
        #expect(!run(freshDefaults(), bundle: nil))
    }
}
