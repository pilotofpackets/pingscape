import XCTest

/// The controls on the detail pages and inside the tools: every button,
/// switch, picker and menu does what it says, in the text size, appearance
/// and orientation of the run.
@MainActor
final class DetailPageFlowTests: UITestCase {
    let config = TestConfig.current.english

    func label(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testWiFiMeasuresTheRouter() {
        let app = launch(.overview(path: ["wifi"]), config: config)
        let measure = app.buttons["Measure"]
        guard app.scrollTo(measure) || expect(measure) else { return }
        measure.tap()
        // Latency · jitter · loss, from ten pings in demo mode.
        expect(label(app, containing: " ms · "), "the measurement result", timeout: 10)
        XCTAssertFalse(app.buttons["Measure"].exists && !app.buttons["Measure"].isEnabled, "The button stays disabled")
    }

    func testDNSMeasuresResponseTimes() {
        let app = launch(.overview(path: ["dns"]), config: config)
        let measure = app.buttons["Measure response time"]
        guard app.scrollTo(measure) || expect(measure) else { return }
        measure.tap()
        expect(label(app, containing: "ms"), "a response time", timeout: 10)
    }

    /// With external requests off, "Load" asks once; the address then
    /// shows, and the page can be copied.
    func testExternalLoadsOnRequest() {
        let app = launch(.overview(path: ["external"]), config: config, extra: ["-externalLookups", "NO"])
        let load = app.buttons["Load"].firstMatch
        guard expect(load) else { return }
        XCTAssertFalse(app.buttons["More"].exists, "Nothing to copy before loading")
        load.tap()
        expect(label(app, containing: "203.0.113."), "the public address after Load", timeout: 10)
        expect(app.buttons["More"], "Copy page once there is a value")
    }

    func testExternalChecksTheInternet() {
        let app = launch(.overview(path: ["external"]), config: config)
        let check = app.buttons["Check internet"]
        guard app.scrollTo(check) || expect(check) else { return }
        check.tap()
        expectGone(check, "the check should replace the button with its result", timeout: 10)
    }

    /// Every detail page with values has "More" with "Copy page" and the
    /// share formats. Interfaces is a list of links and has nothing to copy;
    /// External has values only once they are loaded (the next test).
    func testMoreMenuOnEveryDetailPage() {
        for page in ["wifi", "vpn", "cellular", "routing", "dns", "routing,routes", "interfaces,interface:en0"] {
            let app = launch(.overview(path: page.split(separator: ",").map(String.init)), config: config)
            let more = app.buttons["More"]
            guard expect(more, "on \(page)") else { continue }
            XCTAssertTrue(more.isHittable, "More is not tappable on \(page) [\(config)]")
            more.tap()
            // At the largest text the menu scrolls; its first entries are enough.
            let items = config.textSize.isAccessibilitySize
                ? ["Copy page", "Share as text"] : ["Copy page", "Share as text", "Share as image", "Share as JSON"]
            for item in items {
                expect(app.buttons[item], "\(item) on \(page)", timeout: 3)
            }
            app.buttons["Copy page"].tap()
            expectGone(app.buttons["Copy page"], "the menu should close after copying")
            app.terminate()
        }
    }

    /// Each interface in the list opens its own page and comes back.
    func testInterfacesOpenTheirPages() {
        let app = launch(.overview(path: ["interfaces"]), config: config)
        guard expect(app.navigationBars["Interfaces"]) else { return }
        for name in ["en0", "pdp_ip0", "utun4", "utun2", "awdl0", "lo0"] {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            guard app.scrollTo(row) else {
                XCTFail("\(name) is not in the list or cannot be reached [\(config)]")
                continue
            }
            app.reveal(row)
            row.tap()
            expect(app.navigationBars[name], "the page of \(name)")
            app.goBack(from: name)
            expect(app.navigationBars["Interfaces"], "back from \(name)")
        }
    }
}

@MainActor
final class ToolOptionFlowTests: UITestCase {
    let config = TestConfig.current.english

    func text(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func testPingModeSwitchesToPathMTU() {
        let app = launch(.tool("ping"), config: config)
        let mtu = app.buttons["Path MTU"]
        guard expect(mtu) else { return }
        mtu.tap()
        expect(text(app, startingWith: "Finds the largest packet"), "the path MTU note")
        XCTAssertFalse(app.element("ping.payload").exists, "The payload field belongs to the ping mode")
        app.buttons["Ping"].firstMatch.tap()
        expect(app.element("ping.payload"), "the payload field after switching back")
    }

    func testPacketSizeMenuSetsThePayload() {
        let app = launch(.tool("ping"), config: config)
        let menu = app.buttons["Packet sizes"]
        guard app.scrollTo(menu) || expect(menu) else { return }
        menu.tap()
        let ethernet = app.buttons["1500-byte packet (Ethernet)"]
        guard expect(ethernet) else { return }
        ethernet.tap()
        // 1500 minus 20 bytes of IPv4 and 8 of ICMP header.
        XCTAssertEqual(app.element("ping.payload").value as? String, "1472")
        menu.tap()
        app.buttons["Default (56 bytes payload)"].tap()
        XCTAssertNotEqual(app.element("ping.payload").value as? String, "1472", "Default did not reset the payload")
    }

    func testDNSCompareHidesTheServerChoice() {
        let app = launch(.tool("dns"), config: config)
        let compare = app.switches["Compare servers"]
        guard app.scrollTo(compare) || expect(compare) else { return }
        compare.set(on: true)
        XCTAssertEqual(compare.value as? String, "1")
        expectGone(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Server'")).firstMatch, "the server choice while comparing")
        compare.set(on: false)
        expect(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Server'")).firstMatch, "the server choice after comparing")
    }

    func testDNSSECSwitch() {
        let app = launch(.tool("dns"), config: config)
        let dnssec = app.switches["Request DNSSEC"]
        guard app.scrollTo(dnssec) || expect(dnssec) else { return }
        let before = dnssec.value as? String
        dnssec.set(on: before != "1")
        XCTAssertNotEqual(dnssec.value as? String, before)
    }

    func testPortsWithoutCommonPortsAsksForAList() {
        let app = launch(.tool("ports"), config: config)
        let common = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Common ports'")).firstMatch
        guard app.scrollTo(common) || expect(common) else { return }
        common.set(on: false)
        let list = app.textFields["22,80,443 or 8000-8100"]
        guard expect(list, "the field for a port list") else { return }
        let start = app.element("tool.start")
        if (app.element("tool.field").value as? String)?.hasPrefix("192.168.") == true {
            XCTAssertFalse(start.isEnabled, "Start without ports to scan")
        }
        list.tap()
        list.typeText("22,80")
        app.dismissKeyboard()
        XCTAssertTrue(start.isEnabled, "Start is still off with a port list")
        common.set(on: true)
    }

    /// A target that ran shows up as a recent chip, and the chip fills it in again.
    func testRecentTargets() {
        let app = launch(.tool("ping"), config: config)
        let clear = app.element("tool.clear")
        guard expect(clear) else { return }
        clear.tap()
        let field = app.element("tool.field")
        field.tap()
        field.typeText("127.0.0.1")
        app.dismissKeyboard()
        app.element("tool.start").tap()
        guard expect(app.buttons["Stop"], timeout: 3) else { return }
        app.buttons["Stop"].tap()
        let chip = app.element("tool.recent").buttons["127.0.0.1"]
        guard expect(chip, "the recent target") else { return }
        app.element("tool.clear").tap()
        chip.tap()
        XCTAssertEqual(app.element("tool.field").value as? String, "127.0.0.1")
    }

    func testEveryToolHasAResultToCopyAndShare() {
        for tool in ["ping", "traceroute", "dns", "whois", "ports", "tls", "http", "dualstack", "ntp", "nat"] {
            let app = launch(.tool(tool), config: config)
            let copy = app.buttons["Copy"]
            let share = app.element("share")
            guard expect(copy, "Copy for \(tool)") else { continue }
            XCTAssertTrue(copy.isHittable, "\(tool): Copy is not tappable [\(config)]")
            XCTAssertTrue(share.exists, "\(tool): no share button")
            app.terminate()
        }
    }
}

@MainActor
final class LANAndLiveFlowTests: UITestCase {
    let config = TestConfig.current.english

    func testSearchModeExplainsItself() {
        let app = launch(.lan(), config: config)
        let thorough = app.buttons["Thorough"]
        guard app.scrollTo(thorough) || expect(thorough) else { return }
        thorough.tap()
        expect(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Also tries a few ports'")).firstMatch)
        app.buttons["Quick"].tap()
        expect(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Pings every address'")).firstMatch)
    }

    func testLANShareMenu() {
        let app = launch(.lan(), config: config)
        guard expect(app.element("lan.device.192.168.178.60"), timeout: 15) else { return }
        let share = app.navigationBars.buttons["Share"]
        guard expect(share) else { return }
        share.tap()
        expect(app.buttons["Share list"])
        expect(app.buttons["Share as CSV"])
    }

    func testLiveSwitchesConnections() {
        let app = launch(.live, config: config)
        guard expect(app.navigationBars["Live"]) else { return }
        let picker = app.segmentedControls.firstMatch
        guard expect(picker, "the connection picker") else { return }
        for index in 0..<picker.buttons.count {
            let segment = picker.buttons.element(boundBy: index)
            segment.tap()
            XCTAssertTrue(segment.isSelected, "Segment \(index) is not selected after a tap")
            XCTAssertEqual(app.state, .runningForeground)
        }
    }
}
