import XCTest

/// Every screen of the app, one test each, in the variant of `TestConfig.current`.
///
/// Language independent: the screens are opened with the demo launch
/// arguments, not by tapping titles, so the same tests run in all five languages.
@MainActor
final class OverviewScreenTests: UITestCase {
    func testOverview() { checkScreen("Overview", .overview()) }
    func testWiFi() { checkScreen("Overview › Wi-Fi", .overview(path: ["wifi"])) }
    func testVPN() { checkScreen("Overview › VPN", .overview(path: ["vpn"])) }
    func testCellular() { checkScreen("Overview › Cellular", .overview(path: ["cellular"])) }
    func testDNSAndProxy() { checkScreen("Overview › DNS and Proxy", .overview(path: ["dns"])) }
    func testExternal() { checkScreen("Overview › External", .overview(path: ["external"])) }
}

/// The same pages with the longest values a real network gives: a 32-byte
/// network name without a space, full IPv6 addresses, five DNS servers, two
/// VPNs, a long proxy address, two SIMs.
@MainActor
final class LongValueScreenTests: UITestCase {
    let long = ["-demo-data", "long"]

    func testOverview() { checkScreen("Long values › Overview", .overview(), extra: long) }
    func testWiFi() { checkScreen("Long values › Wi-Fi", .overview(path: ["wifi"]), extra: long) }
    func testVPN() { checkScreen("Long values › VPN", .overview(path: ["vpn"]), extra: long) }
    func testCellular() { checkScreen("Long values › Cellular", .overview(path: ["cellular"]), extra: long) }
    func testDNSAndProxy() { checkScreen("Long values › DNS and Proxy", .overview(path: ["dns"]), extra: long) }
    func testRouting() { checkScreen("Long values › Routing", .overview(path: ["routing"]), extra: long) }
    func testInterfaces() { checkScreen("Long values › Interfaces", .overview(path: ["interfaces"]), extra: long) }
    func testInterfaceWiFi() {
        checkScreen("Long values › Interface en0", .overview(path: ["interfaces", "interface:en0"]), extra: long)
    }
    func testLive() { checkScreen("Long values › Live", .live, extra: long) }
}

/// Split from the overview so the parallel clones share the work: they are
/// handed out one class at a time.
@MainActor
final class RoutingScreenTests: UITestCase {
    func testRouting() { checkScreen("Overview › Routing", .overview(path: ["routing"])) }
    /// A long table of the same kind of row: four pages show every kind.
    func testAllRoutes() { checkScreen("Overview › Routing › All routes", .overview(path: ["routing", "routes"]), maxPages: 4) }
}

@MainActor
final class InterfaceScreenTests: UITestCase {
    func testInterfaces() { checkScreen("Overview › Interfaces", .overview(path: ["interfaces"])) }
    func testInterfaceWiFi() { checkScreen("Overview › Interface en0", .overview(path: ["interfaces", "interface:en0"])) }
    func testInterfaceCellular() {
        checkScreen("Overview › Interface pdp_ip0", .overview(path: ["interfaces", "interface:pdp_ip0"]))
    }
    func testInterfaceTunnel() {
        checkScreen("Overview › Interface utun4", .overview(path: ["interfaces", "interface:utun4"]))
    }
    func testInterfaceAWDL() { checkScreen("Overview › Interface awdl0", .overview(path: ["interfaces", "interface:awdl0"])) }
    func testInterfaceLoopback() { checkScreen("Overview › Interface lo0", .overview(path: ["interfaces", "interface:lo0"])) }
}

@MainActor
final class LANScreenTests: UITestCase {
    func testDeviceList() {
        checkScreen("LAN", .lan()) { $0.element("lan.device.192.168.178.60") }
    }
    func testRouter() { checkScreen("LAN › Router", .lan(device: "192.168.178.1")) }
    func testTV() { checkScreen("LAN › TV", .lan(device: "192.168.178.40")) }
    func testPrinter() { checkScreen("LAN › Printer", .lan(device: "192.168.178.52")) }
    func testNAS() { checkScreen("LAN › NAS", .lan(device: "192.168.178.60")) }
    func testUnnamedDevice() { checkScreen("LAN › Unnamed device", .lan(device: "192.168.178.23")) }
}

@MainActor
final class LiveScreenTests: UITestCase {
    func testLive() { checkScreen("Live", .live) }
}

@MainActor
final class ToolScreenTests: UITestCase {
    func testPing() { checkScreen("Tools › Ping", .tool("ping")) }
    func testPathMTU() { checkScreen("Tools › Ping › Path MTU", .tool("ping", extra: ["-demo-ping", "mtu"])) }
    func testTraceroute() { checkScreen("Tools › Traceroute", .tool("traceroute")) }
    func testMTR() { checkScreen("Tools › Traceroute › Continuous", .tool("traceroute", extra: ["-demo-traceroute", "mtr"])) }
    func testDNS() { checkScreen("Tools › DNS", .tool("dns")) }
    func testDNSCompare() { checkScreen("Tools › DNS › Compare", .tool("dns", extra: ["-demo-dns", "compare"])) }
}

@MainActor
final class LookupToolScreenTests: UITestCase {
    func testWhois() { checkScreen("Tools › Whois", .tool("whois")) }
    func testPorts() { checkScreen("Tools › Ports", .tool("ports")) }
    func testTLS() { checkScreen("Tools › TLS", .tool("tls")) }
    func testHTTP() { checkScreen("Tools › HTTP", .tool("http")) }
    func testSubnet() { checkScreen("Tools › Subnet", .tool("subnet")) }
    func testOUI() { checkScreen("Tools › OUI", .tool("oui")) }
}

@MainActor
final class NewToolScreenTests: UITestCase {
    func testDualStack() { checkScreen("Tools › Dual stack", .tool("dualstack")) }
    func testNTP() { checkScreen("Tools › NTP", .tool("ntp")) }
    func testNAT() { checkScreen("Tools › NAT", .tool("nat")) }
}

@MainActor
final class AboutScreenTests: UITestCase {
    func testAbout() { checkScreen("About", .about) }
    func testShortcutsHelp() { checkScreen("About › Siri and Shortcuts", .shortcutsHelp) }

    func testDiagnosticDump() {
        let config = TestConfig.current
        let app = launch(.about, config: config)
        let link = app.element("about.dump")
        guard app.scrollTo(link) || expect(link) else { return }
        link.tap()
        expect(app.element("dump.anonymize"))
        ScreenCheck(test: self, app: app, config: config).run("About › Diagnostic dump")
    }

    func testLicenses() {
        let config = TestConfig.current
        let app = launch(.about, config: config)
        let link = app.element("about.licenses")
        guard app.scrollTo(link) || expect(link) else { return }
        link.tap()
        ScreenCheck(test: self, app: app, config: config).settle()
        ScreenCheck(test: self, app: app, config: config).run("About › Licenses")
    }
}

@MainActor
final class FirstRunScreenTests: UITestCase {
    /// The six pages of the tour, then the question about external requests.
    func testTourAndExternalPrompt() {
        let config = TestConfig.current
        let app = launch(.firstRun, config: config)
        let check = ScreenCheck(test: self, app: app, config: config)
        let next = app.element("onboarding.next")
        guard expect(next, timeout: 15) else { return }
        for page in 1...6 {
            check.run("Introduction \(page)", scroll: false)
            guard next.exists else {
                XCTFail("No “Next” button on page \(page)")
                return
            }
            XCTAssertTrue(next.isHittable, "“Next” is not tappable on page \(page) [\(config)]")
            if page < 6 {
                XCTAssertTrue(app.element("onboarding.skip").exists, "No “Skip” on page \(page)")
            }
            next.tap()
        }
        let no = app.element("externalPrompt.no")
        guard expect(no, "after the tour") else { return }
        check.run("External requests prompt")
        let yes = app.element("externalPrompt.yes")
        XCTAssertTrue(app.scrollTo(yes), "“Yes, show” cannot be reached [\(config)]")
        XCTAssertTrue(app.scrollTo(no), "“Not now” cannot be reached [\(config)]")
    }
}
