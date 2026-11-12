import XCTest

/// Where the app starts. Everything runs in demo mode: fixed data, no network,
/// so every simulator shows the same thing.
enum Start {
    case overview(path: [String] = [])
    case lan(device: String? = nil)
    case live
    case tool(String, extra: [String] = [])
    case about
    /// The first launch: the tour, then the question about external requests.
    case firstRun

    var arguments: [String] {
        switch self {
        case .overview(let path):
            ["-demo-tab", "overview"] + (path.isEmpty ? [] : ["-demo-path", path.joined(separator: ",")])
        case .lan(let device):
            ["-demo-tab", "lan"] + (device.map { ["-demo-lan-device", $0] } ?? [])
        case .live: ["-demo-tab", "live"]
        case .tool(let tool, let extra): ["-demo-tab", "tools", "-demo-tool", tool] + extra
        case .about: ["-demo-tab", "about"]
        case .firstRun: ["-demo-tab", "overview", "-demo-firstrun", "1"]
        }
    }
}

/// "Hide values by default" at launch.
enum HideValues {
    /// As `TestConfig.hideValues` says.
    case asConfigured
    case on
    case off
    /// What the app has stored, for a test of the setting itself.
    case stored
}

@MainActor
extension XCTestCase {
    /// Launches the app in demo mode at `start`, in the variant `config`.
    ///
    /// Settings are passed as arguments, which win over what an earlier test
    /// left in `UserDefaults`.
    @discardableResult
    func launch(
        _ start: Start, config: TestConfig = .current, hideValues: HideValues = .asConfigured,
        extra: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments: [String] = [
            "-AppleLanguages", "(\(config.language))",
            "-AppleLocale", config.locale,
            "-UIPreferredContentSizeCategoryName", config.textSize.category,
        ]
        // `UserDefaults` arguments have to come before `-demo`: the app reads
        // the value after `-demo-…` flags itself and would swallow them.
        switch hideValues {
        case .asConfigured: arguments += ["-hideValuesByDefault", config.hideValues ? "YES" : "NO"]
        case .on: arguments += ["-hideValuesByDefault", "YES"]
        case .off: arguments += ["-hideValuesByDefault", "NO"]
        case .stored: break
        }
        if case .firstRun = start {
            arguments += ["-onboardingShown", "NO", "-externalPromptShown", "NO", "-externalLookups", "NO"]
        } else {
            arguments += ["-onboardingShown", "YES", "-externalPromptShown", "YES"]
        }
        arguments += extra
        arguments.append("-demo")
        arguments += start.arguments
        app.launchArguments = arguments

        XCUIDevice.shared.appearance = config.dark ? .dark : .light
        XCUIDevice.shared.orientation = config.landscape ? .landscapeLeft : .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "The app did not start")
        return app
    }

    /// Waits until `element` exists, and fails with `message` if it does not.
    @discardableResult
    func expect(
        _ element: XCUIElement, _ message: String = "", timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) -> Bool {
        let exists = element.waitForExistence(timeout: timeout)
        if !exists {
            XCTFail("Not found: \(element.description) \(message)", file: file, line: line)
        }
        return exists
    }

    /// Waits until `element` is gone.
    func expectGone(
        _ element: XCUIElement, _ message: String = "", timeout: TimeInterval = 5,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        if XCTWaiter().wait(for: [gone], timeout: timeout) != .completed {
            XCTFail("Still there: \(element.description) \(message)", file: file, line: line)
        }
    }
}

@MainActor
extension XCUIApplication {
    /// A tab by its English title, in the tab bar (iPhone) or the floating
    /// tab bar or sidebar (iPad).
    func tab(_ title: String) -> XCUIElement {
        let inBar = tabBars.buttons[title]
        if inBar.exists { return inBar }
        let button = buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if button.exists { return button }
        // The iPad's tab bar at the top shows only what fits; at large text
        // sizes the last tabs are behind its arrow. The sidebar lists them all.
        let sidebar = buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
        if sidebar.exists {
            sidebar.tap()
            _ = button.waitForExistence(timeout: 2)
        }
        return button
    }

    /// The text field, button or row with this accessibility identifier.
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier].firstMatch
    }

    /// Scrolls the main content up by most of a screen, slowly so it does not
    /// fling past anything.
    func scrollPage(down: Bool = true) {
        let window = windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.72 : 0.3))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.3 : 0.72))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    /// Closes the keyboard with the app's own Done button and waits until it
    /// is gone. Checking for Done once, right after typing, came too early
    /// while the keyboard was still moving in: it stayed open, and the next
    /// tap meant for a tab typed "z" and ".com" into the field instead.
    func dismissKeyboard(file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 1) else { return }
        let done = element("keyboard.done")
        if done.waitForExistence(timeout: 3) {
            done.tap()
        } else {
            XCTFail("The keyboard is open but there is no Done button", file: file, line: line)
            return
        }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keyboard)
        if XCTWaiter().wait(for: [gone], timeout: 5) != .completed {
            XCTFail("Done did not close the keyboard", file: file, line: line)
        }
    }

    /// Swipes a sideways scroller until `element` can be tapped.
    @discardableResult
    func scrollSideways(_ scroller: XCUIElement, toReveal element: XCUIElement, swipes: Int = 6) -> Bool {
        let window = windows.firstMatch.frame
        // Its middle on screen: at the largest text a chip can be wider than
        // the space between the edges of the scroller.
        let visible = {
            element.exists && window.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
                && element.frame.minX >= window.minX - 1
        }
        for direction in [true, false] {
            for _ in 0..<swipes {
                if visible() { return true }
                let from = scroller.coordinate(withNormalizedOffset: CGVector(dx: direction ? 0.8 : 0.2, dy: 0.5))
                let to = scroller.coordinate(withNormalizedOffset: CGVector(dx: direction ? 0.3 : 0.7, dy: 0.5))
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
            }
        }
        return visible()
    }

    /// Scrolls `element` fully into the free area between the bars: a tall
    /// row at the largest text could count as hittable while its switch lay
    /// under the tab bar.
    func reveal(_ element: XCUIElement) {
        let window = windows.firstMatch.frame
        for _ in 0..<6 {
            guard element.exists else { return }
            let top = (navigationBars.allElementsBoundByIndex.map(\.frame).filter { $0.intersects(window) }.map(\.maxY).max() ?? 0) + 8
            let bottom = (tabBars.firstMatch.exists ? tabBars.firstMatch.frame.minY : window.maxY) - 16
            let frame = element.frame
            let shift: CGFloat
            if frame.maxY > bottom {
                shift = -min(frame.maxY - bottom + 24, window.height * 0.4)
            } else if frame.minY < top {
                shift = min(top - frame.minY + 24, window.height * 0.4)
            } else {
                return
            }
            let start = window.height * 0.5
            let from = windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: start))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: shift)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    /// Scrolls until `element` is hittable, at most `pages` pages.
    @discardableResult
    func scrollTo(_ element: XCUIElement, pages: Int = 25) -> Bool {
        for _ in 0..<pages {
            if element.exists, element.isHittable { return true }
            scrollPage()
        }
        return element.exists && element.isHittable
    }
}

@MainActor
extension XCUIElement {
    /// Turns a switch on or off. Taps the switch itself: a tap on the middle
    /// of the row can land on its label, which does nothing.
    func set(on: Bool) {
        guard (value as? String == "1") != on else { return }
        XCUIApplication().reveal(self)
        // The switch sits at the right of its row, or at the largest text
        // sizes under the label at the left. Try where it can be until it flips.
        let control = switches.firstMatch.exists ? switches.firstMatch : self
        let spots = [CGVector(dx: 0.95, dy: 0.5), CGVector(dx: 0.9, dy: 0.85), CGVector(dx: 0.12, dy: 0.85), CGVector(dx: 0.5, dy: 0.5)]
        for spot in spots {
            control.coordinate(withNormalizedOffset: spot).tap()
            if (value as? String == "1") == on { return }
        }
    }
}
