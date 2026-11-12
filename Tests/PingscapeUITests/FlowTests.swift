import XCTest

/// What a user does: switch tabs, open pages, type, hide values, go through
/// the first launch. In English (titles are looked up), but in the text size,
/// appearance and orientation of the run.
@MainActor
final class NavigationFlowTests: UITestCase {
    let config = TestConfig.current.english

    func testEveryTabOpens() {
        let app = launch(.overview(), config: config)
        expect(app.navigationBars["Overview"])
        for (tab, title) in [("LAN", "LAN"), ("Live", "Live"), ("Tools", "Tools"), ("About", "About"), ("Overview", "Overview")] {
            let button = app.tab(tab)
            guard expect(button, "tab \(tab)") else { continue }
            XCTAssertTrue(button.isHittable, "Tab \(tab) is not tappable [\(config)]")
            button.tap()
            expect(app.navigationBars[title], "after tapping \(tab)")
        }
    }

    func testOverviewLinksOpenTheirPages() {
        let app = launch(.overview(), config: config)
        let pages = ["Routing", "DNS and Proxy", "External", "Interfaces"]
        for page in pages {
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", page)).firstMatch
            guard expect(link, "link \(page)"), app.scrollTo(link) else {
                XCTFail("Link \(page) cannot be reached [\(config)]")
                continue
            }
            link.tap()
            guard expect(app.navigationBars[page], "page \(page)") else { continue }
            app.goBack(from: page)
            expect(app.navigationBars["Overview"], "back from \(page)")
        }
    }

    func testDetailsLinksOfTheCards() {
        let app = launch(.overview(), config: config)
        expect(app.navigationBars["Overview"])
        let details = app.buttons.matching(NSPredicate(format: "label == 'Details'"))
        let count = details.count
        XCTAssertGreaterThanOrEqual(count, 3, "Wi-Fi, VPN and Cellular should each have “Details”")
        for index in 0..<count {
            let link = details.element(boundBy: index)
            guard app.scrollTo(link) else {
                XCTFail("Details link \(index + 1) cannot be reached [\(config)]")
                continue
            }
            link.tap()
            XCTAssertFalse(app.navigationBars["Overview"].waitForExistence(timeout: 1), "Details \(index + 1) did not open a page")
            app.goBack()
            expect(app.navigationBars["Overview"])
        }
    }

    /// Rotating keeps the page that is open. On the iPad, landscape adds the
    /// sidebar with a navigation bar of its own, so the page is looked up by
    /// its title, not as the first bar.
    func testRotationKeepsThePage() {
        guard !config.landscape else { return }
        let app = launch(.overview(path: ["wifi"]), config: config)
        guard expect(app.navigationBars["Wi-Fi"]) else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
        expect(app.navigationBars["Wi-Fi"], "Rotating to landscape left the page")
        ScreenCheck(test: self, app: app, config: config).run("Wi-Fi, rotated")
        XCUIDevice.shared.orientation = .portrait
        expect(app.navigationBars["Wi-Fi"], "Rotating back left the page")
    }

    func testBackgroundAndBack() {
        let app = launch(.tool("ping"), config: config)
        expect(app.navigationBars["Tools"])
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5) || app.wait(for: .runningBackgroundSuspended, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        expect(app.navigationBars["Tools"], "after returning to the app")
        XCTAssertTrue(app.element("tool.chip.ping").isSelected, "The selected tool changed after the app was in the background")
    }

    func testPullToRefresh() {
        let app = launch(.overview(), config: config)
        expect(app.navigationBars["Overview"])
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertEqual(app.state, .runningForeground)
        expect(app.navigationBars["Overview"])
    }

    func testShareMenuOffersAllFormats() {
        let app = launch(.overview(), config: config)
        let share = app.element("share")
        guard expect(share) else { return }
        XCTAssertTrue(share.isHittable)
        share.tap()
        for item in ["Share as text", "Share as image", "Save image to Photos", "Share as JSON"] {
            expect(app.buttons[item], "in the share menu", timeout: 3)
        }
        // Close the menu without choosing.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.95)).tap()
        expectGone(app.buttons["Share as JSON"])
    }
}

@MainActor
final class PrivacyFlowTests: UITestCase {
    let config = TestConfig.current.english

    /// Text that looks like an address, a MAC or the demo network's name.
    static let identifying: [(String, NSRegularExpression)] = [
        ("IPv4 address or mask", try! NSRegularExpression(pattern: #"\b\d{1,3}(\.\d{1,3}){3}\b"#)),
        ("IPv6 address", try! NSRegularExpression(pattern: #"\b([0-9a-fA-F]{1,4}:){3,}[0-9a-fA-F]{1,4}\b|[0-9a-fA-F]{1,4}::[0-9a-fA-F]{0,4}|::1\b"#)),
        ("network name", try! NSRegularExpression(pattern: "HomeNet")),
    ]

    /// Every label and value on screen, page by page to the end.
    func allText(_ app: XCUIApplication, pages: Int = 10) -> Set<String> {
        var texts: Set<String> = []
        var last = ""
        for _ in 0..<pages {
            guard let snapshot = try? app.snapshot() else { break }
            let fingerprint = ScreenCheck.fingerprint(snapshot)
            if fingerprint == last { break }
            last = fingerprint
            func visit(_ element: XCUIElementSnapshot) {
                if !element.label.isEmpty { texts.insert(element.label) }
                if let value = element.value as? String, !value.isEmpty { texts.insert(value) }
                element.children.forEach(visit)
            }
            visit(snapshot)
            app.scrollPage()
        }
        return texts
    }

    func leaks(in texts: Set<String>) -> [String] {
        texts.flatMap { text in
            Self.identifying.compactMap { name, pattern in
                pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil ? nil : "\(name): “\(text)”"
            }
        }.sorted()
    }

    /// With "Hide values" on, no page of the overview shows an address,
    /// a mask, a MAC or the network name.
    func testHiddenValuesOnEveryOverviewPage() {
        let pages: [(String, [String])] = [
            ("Overview", []), ("Wi-Fi", ["wifi"]), ("VPN", ["vpn"]), ("Cellular", ["cellular"]),
            ("Routing", ["routing"]), ("All routes", ["routing", "routes"]), ("DNS and Proxy", ["dns"]),
            ("External", ["external"]), ("Interfaces", ["interfaces"]),
            ("en0", ["interfaces", "interface:en0"]), ("utun4", ["interfaces", "interface:utun4"]),
            ("pdp_ip0", ["interfaces", "interface:pdp_ip0"]), ("utun2", ["interfaces", "interface:utun2"]),
        ]
        for (name, path) in pages {
            let app = launch(.overview(path: path), config: config, hideValues: .on)
            guard expect(app.navigationBars.firstMatch, name) else { continue }
            for leak in leaks(in: allText(app)) {
                XCTFail("\(name) shows with hidden values: \(leak)")
            }
            app.terminate()
        }
    }

    func testHiddenValuesInTheLAN() {
        for device in [nil, "192.168.178.1", "192.168.178.40", "192.168.178.60"] {
            let app = launch(.lan(device: device), config: config, hideValues: .on)
            guard expect(app.navigationBars.firstMatch) else { continue }
            if device == nil { _ = app.element("lan.device.192.168.178.60").waitForExistence(timeout: 10) }
            for leak in leaks(in: allText(app)) {
                XCTFail("LAN \(device ?? "list") shows with hidden values: \(leak)")
            }
            app.terminate()
        }
    }

    /// The eye in the toolbar hides and shows again.
    func testEyeTogglesTheValues() {
        let app = launch(.overview(), config: config, hideValues: .off)
        let eye = app.element("overview.hideValues")
        guard expect(eye) else { return }
        let address = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '192.168.178.42'")).firstMatch
        expect(address, "the IP address before hiding")
        eye.tap()
        XCTAssertTrue(eye.isSelected, "The eye is not marked as selected")
        expectGone(address, "after tapping the eye")
        eye.tap()
        expect(address, "after tapping the eye again")
    }

    /// A long press hides one value and leaves the others.
    func testLongPressHidesOneValue() {
        let app = launch(.overview(), config: config, hideValues: .off)
        let rows = { (label: String) in
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        }
        let row = rows("IP address")
        let other = rows("Subnet mask")
        guard expect(row), expect(other) else { return }
        let before = row.label
        let otherBefore = other.label
        XCTAssertFalse(before.contains("•"), "The address is hidden before the long press")
        row.press(forDuration: 1.2)
        let hide = app.buttons["Hide value"]
        guard expect(hide, "in the context menu") else { return }
        hide.tap()
        expectGone(hide)
        XCTAssertTrue(row.label.contains("•••"), "The row still shows its value: \(row.label)")
        XCTAssertEqual(other.label, otherBefore, "Another row was hidden too")
        XCTAssertFalse(app.element("overview.hideValues").isSelected, "Hiding one value switched on hiding all")

        row.press(forDuration: 1.2)
        let show = app.buttons["Show value"]
        guard expect(show, "the context menu offers to show it again") else { return }
        show.tap()
        expectGone(show)
        XCTAssertEqual(row.label, before, "The value did not come back")
    }

    /// The stored setting decides how the next launch starts.
    func testHideByDefaultSetting() {
        var app = launch(.about, config: config, hideValues: .stored)
        let toggle = app.element("about.hideByDefault")
        guard app.scrollTo(toggle) || expect(toggle) else { return }
        toggle.set(on: true)
        XCTAssertEqual(toggle.value as? String, "1")
        app.terminate()

        app = launch(.overview(), config: config, hideValues: .stored)
        expect(app.navigationBars["Overview"])
        XCTAssertTrue(app.element("overview.hideValues").isSelected, "Values are not hidden at launch with the setting on")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '192.168.178.42'")).firstMatch.exists)
        app.terminate()

        app = launch(.about, config: config, hideValues: .stored)
        let again = app.element("about.hideByDefault")
        if app.scrollTo(again) || expect(again) { again.set(on: false) }
        XCTAssertEqual(again.value as? String, "0")
    }

    /// The anonymized diagnostic dump holds none of the demo addresses.
    func testDiagnosticDumpIsAnonymized() {
        let app = launch(.about, config: config)
        let link = app.element("about.dump")
        guard app.scrollTo(link) || expect(link) else { return }
        link.tap()
        let toggle = app.element("dump.anonymize")
        guard expect(toggle) else { return }
        XCTAssertEqual(toggle.value as? String, "1", "Anonymizing should be on by default")
        let content = { app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'snapshot' OR label CONTAINS '{'")).firstMatch }
        // The list makes its rows only when they come on screen: at AX5 the
        // content is below the long footer.
        guard app.scrollTo(content()) || expect(content(), "the dump") else { return }
        for secret in ["192.168.178.42", "HomeNet", "3C:A6:2F:1B:D3:22", "2001:db8:4a1c"] {
            XCTAssertFalse(content().label.contains(secret), "The anonymized dump contains \(secret)")
        }
        toggle.set(on: false)
        XCTAssertTrue(app.scrollTo(content()), "The dump is gone after the switch [\(config)]")
        XCTAssertTrue(content().label.contains("192.168.178.42"), "With the switch off the dump should hold the real address")
    }
}

@MainActor
final class ToolFlowTests: UITestCase {
    let config = TestConfig.current.english

    static let tools = ["ping", "traceroute", "dns", "whois", "ports", "tls", "http", "dualstack", "ntp", "nat", "subnet", "oui"]
    static let withoutStart: Set<String> = ["subnet", "oui"]

    func testEveryChipSelectsItsTool() {
        let app = launch(.tool("ping"), config: config)
        expect(app.navigationBars["Tools"])
        for tool in Self.tools {
            let chip = app.element("tool.chip.\(tool)")
            guard expect(chip, "chip \(tool)") else { continue }
            guard app.scrollSideways(app.element("tool.chips"), toReveal: chip) else {
                XCTFail("Chip \(tool) cannot be scrolled into view [\(config)]")
                continue
            }
            chip.tap()
            XCTAssertTrue(chip.isSelected, "Chip \(tool) is not selected after a tap")
            let start = app.element("tool.start")
            if Self.withoutStart.contains(tool) {
                XCTAssertFalse(start.exists, "\(tool) should have no Start button")
            } else {
                XCTAssertTrue(start.waitForExistence(timeout: 2), "\(tool) has no Start button")
                XCTAssertTrue(start.isHittable, "Start of \(tool) is not tappable [\(config)]")
            }
            XCTAssertTrue(app.element("tool.field").exists, "\(tool) has no input field")
        }
    }

    /// With the keyboard open, the field, Start and Done stay above it and
    /// can be tapped, and Done closes it (the bug of 2026-09-30).
    func testKeyboardLeavesFieldStartAndDoneReachable() {
        for tool in Self.tools {
            let app = launch(.tool(tool), config: config)
            let field = app.element("tool.field")
            guard expect(field, tool) else { continue }
            field.tap()
            let keyboard = app.keyboards.firstMatch
            guard keyboard.waitForExistence(timeout: 5) else {
                XCTFail("\(tool): no software keyboard. Run scripts/ui-matrix.sh, which turns off the hardware keyboard of the simulator.")
                app.terminate()
                continue
            }
            ScreenCheck(test: self, app: app, config: config).settle()
            ScreenCheck(test: self, app: app, config: config).attachScreenshot("\(tool) with keyboard")
            let top = keyboard.frame.minY

            XCTAssertLessThanOrEqual(field.frame.maxY, top + 1, "\(tool): the field is behind the keyboard [\(config)]")
            let done = app.element("keyboard.done")
            if expect(done, "\(tool): Done") {
                XCTAssertTrue(done.isHittable, "\(tool): Done is not tappable [\(config)]")
                XCTAssertLessThanOrEqual(done.frame.maxY, top + 1, "\(tool): Done is behind the keyboard [\(config)]")
            }
            if !Self.withoutStart.contains(tool) {
                let start = app.element("tool.start")
                if expect(start, "\(tool): Start") {
                    XCTAssertTrue(start.isHittable, "\(tool): Start is not tappable with the keyboard open [\(config)]")
                    XCTAssertLessThanOrEqual(start.frame.maxY, top + 1, "\(tool): Start is behind the keyboard [\(config)]")
                    if done.exists {
                        XCTAssertFalse(start.frame.intersects(done.frame), "\(tool): Start and Done overlap [\(config)]")
                    }
                }
            }
            if done.exists {
                done.tap()
                expectGone(keyboard, "\(tool): Done did not close the keyboard")
            }
            app.terminate()
        }
    }

    func testClearEmptiesTheFieldAndDisablesStart() {
        for tool in ["ping", "dns", "whois", "tls", "http", "dualstack"] {
            let app = launch(.tool(tool), config: config)
            let clear = app.element("tool.clear")
            guard expect(clear, tool) else { continue }
            clear.tap()
            expectGone(app.element("tool.clear"), "\(tool): the clear button stays on an empty field")
            let start = app.element("tool.start")
            XCTAssertFalse(start.isEnabled, "\(tool): Start is enabled with an empty field")
            app.terminate()
        }
    }

    /// A target that is no host name or address is turned down without a crash,
    /// and the tool does not start.
    func testInvalidInputIsRejected() {
        for tool in ["ping", "traceroute", "dns", "tls", "http", "dualstack", "ntp", "nat"] {
            let app = launch(.tool(tool), config: config)
            let field = app.element("tool.field")
            guard expect(field, tool) else { continue }
            // NTP and NAT start with an empty field: their own server is optional.
            let clear = app.element("tool.clear")
            if clear.waitForExistence(timeout: 2) { clear.tap() }
            field.tap()
            field.typeText("keinhost!!!")
            let start = app.element("tool.start")
            app.dismissKeyboard()
            start.tap()
            XCTAssertEqual(app.state, .runningForeground, "\(tool) crashed on invalid input")
            XCTAssertFalse(app.buttons["Stop"].waitForExistence(timeout: 1), "\(tool) started with invalid input")
            ScreenCheck(test: self, app: app, config: config).attachScreenshot("\(tool) invalid input")
            app.terminate()
        }
    }

    /// Switching to another tab stops a running tool (found 2026-11-01).
    func testLeavingTheTabStopsARun() {
        let app = launch(.tool("ping"), config: config)
        let clear = app.element("tool.clear")
        guard expect(clear) else { return }
        clear.tap()
        let field = app.element("tool.field")
        field.tap()
        field.typeText("127.0.0.1")
        app.dismissKeyboard()
        let start = app.element("tool.start")
        start.tap()
        guard expect(app.buttons["Stop"], "after Start", timeout: 3) else { return }
        app.tab("Overview").tap()
        app.tab("Tools").tap()
        expect(app.buttons["Start"], "the ping should have stopped when the tab was left", timeout: 3)
    }
}

@MainActor
final class LANFlowTests: UITestCase {
    let config = TestConfig.current.english

    func testDeviceOpensToolsWithItsAddress() {
        for (action, chip) in [("lan.action.ping", "ping"), ("lan.action.ports", "ports"), ("lan.action.traceroute", "traceroute")] {
            let app = launch(.lan(), config: config)
            let device = app.element("lan.device.192.168.178.52")
            guard expect(device, "the printer in the list", timeout: 15), app.scrollTo(device) else { continue }
            device.tap()
            let button = app.element(action)
            guard expect(button), app.scrollTo(button) else { continue }
            button.tap()
            expect(app.navigationBars["Tools"], "after \(action)")
            XCTAssertTrue(app.element("tool.chip.\(chip)").isSelected, "\(chip) is not the selected tool")
            XCTAssertEqual(app.element("tool.field").value as? String, "192.168.178.52", "\(chip) does not have the address")
            app.terminate()
        }
    }

    func testThisDeviceOpensWiFi() {
        let app = launch(.lan(), config: config)
        let me = app.element("lan.device.192.168.178.42")
        guard expect(me, timeout: 15), app.scrollTo(me) else { return }
        me.tap()
        expect(app.navigationBars["Wi-Fi"], "tapping this iPhone should open the Wi-Fi page")
    }

    func testSearchAgain() {
        let app = launch(.lan(), config: config)
        let search = app.element("lan.search")
        guard expect(search, timeout: 15), app.scrollTo(search) else { return }
        search.tap()
        expect(app.element("lan.device.192.168.178.60"), "after searching again", timeout: 15)
    }
}

@MainActor
final class FirstRunFlowTests: UITestCase {
    let config = TestConfig.current.english

    func testSkipThenNotNow() {
        let app = launch(.firstRun, config: config)
        let skip = app.element("onboarding.skip")
        guard expect(skip, timeout: 15) else { return }
        skip.tap()
        let no = app.element("externalPrompt.no")
        guard app.scrollTo(no) || expect(no) else { return }
        no.tap()
        expectGone(no)
        expect(app.navigationBars["Overview"])
        app.tab("About").tap()
        let toggle = app.element("about.externalRequests")
        if expect(toggle) { XCTAssertEqual(toggle.value as? String, "0", "“Not now” must leave external requests off") }
    }

    func testYesTurnsOnExternalRequests() {
        let app = launch(.firstRun, config: config)
        let skip = app.element("onboarding.skip")
        guard expect(skip, timeout: 15) else { return }
        skip.tap()
        let yes = app.element("externalPrompt.yes")
        guard app.scrollTo(yes) || expect(yes) else { return }
        yes.tap()
        expectGone(yes)
        app.tab("About").tap()
        let toggle = app.element("about.externalRequests")
        if expect(toggle) { XCTAssertEqual(toggle.value as? String, "1", "“Yes, show” must turn external requests on") }
    }

    func testTourCanBeShownAgainFromAbout() {
        let app = launch(.about, config: config)
        let intro = app.element("about.intro")
        guard app.scrollTo(intro) || expect(intro) else { return }
        intro.tap()
        let next = app.element("onboarding.next")
        guard expect(next) else { return }
        for _ in 1...6 { next.tap() }
        expectGone(next, "“Get started” did not close the tour")
        expect(app.navigationBars["About"])
        XCTAssertFalse(app.element("externalPrompt.no").exists, "The prompt must not come again from About")
    }
}

@MainActor
final class SettingsFlowTests: UITestCase {
    let config = TestConfig.current.english

    func testUnitsChangeTheLiveTab() {
        let app = launch(.about, config: config, extra: ["-rateUnit", "megabitPerSecond"])
        let units = app.element("about.units")
        guard app.scrollTo(units) || expect(units) else { return }
        units.tap()
        let megabytes = app.buttons["MB/s"]
        guard expect(megabytes, "in the units menu") else { return }
        megabytes.tap()
        app.tab("Live").tap()
        let rate = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'B/s'")).firstMatch
        expect(rate, "a rate in MB/s or kB/s")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'bit/s'")).firstMatch.exists, "Live still shows bit/s")
        app.tab("About").tap()
        if app.scrollTo(units) {
            units.tap()
            app.buttons["Mbit/s"].tap()
        }
    }

    func testLiveInternetHostField() {
        let app = launch(.live, config: config)
        let toggle = app.element("live.internetToggle")
        guard app.scrollTo(toggle) || expect(toggle) else { return }
        toggle.set(on: true)
        let host = app.element("live.host")
        guard expect(host, "the host field") else { return }
        _ = app.scrollTo(host)
        host.tap()
        let keyboard = app.keyboards.firstMatch
        if keyboard.waitForExistence(timeout: 5) {
            XCTAssertLessThanOrEqual(host.frame.maxY, keyboard.frame.minY + 1, "The host field is behind the keyboard [\(config)]")
            ScreenCheck(test: self, app: app, config: config).attachScreenshot("Live host field with keyboard")
        }
        toggle.set(on: false)
    }
}
