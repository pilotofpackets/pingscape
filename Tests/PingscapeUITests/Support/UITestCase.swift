import XCTest

/// The base of every UI test: keeps going after a failure, so one run lists
/// everything, and puts a screenshot next to every failure.
class UITestCase: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = true
    }

    override func record(_ issue: XCTIssue) {
        var issue = issue
        let screenshot = MainActor.assumeIsolated { XCUIScreen.main.screenshot() }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Screen at failure"
        attachment.lifetime = .keepAlways
        issue.add(attachment)
        super.record(issue)
    }
}
