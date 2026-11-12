import Foundation
import NetKit
import Testing

@testable import Pingscape

@MainActor
@Suite("Hiding values")
struct PrivacyMaskTests {
    @Test("The placeholder has a fixed length, so it does not tell IPv4 from IPv6")
    func placeholder() {
        #expect(PrivacyMask.placeholder == "•••••••")
        let mask = PrivacyMask()
        mask.isMasked = true
        #expect(mask.shown("1.1.1.1") == mask.shown("2001:db8::1"))
    }

    @Test("Unmasked values are shown as they are")
    func unmasked() {
        let mask = PrivacyMask()
        mask.isMasked = false
        #expect(mask.shown("192.168.178.42") == "192.168.178.42")
    }

    @Test("A single value is hidden and shown again by label and value together")
    func individually() {
        let mask = PrivacyMask()
        #expect(!mask.isIndividuallyHidden(label: "DNS server 1", value: "1.1.1.1"))
        mask.toggleIndividuallyHidden(label: "DNS server 1", value: "1.1.1.1")
        #expect(mask.isIndividuallyHidden(label: "DNS server 1", value: "1.1.1.1"))
        // Same value under another label, same label with another value: not hidden.
        #expect(!mask.isIndividuallyHidden(label: "DNS server 2", value: "1.1.1.1"))
        #expect(!mask.isIndividuallyHidden(label: "DNS server 1", value: "8.8.8.8"))
        mask.toggleIndividuallyHidden(label: "DNS server 1", value: "1.1.1.1")
        #expect(!mask.isIndividuallyHidden(label: "DNS server 1", value: "1.1.1.1"))
    }

    @Test("Label and value cannot run into each other in the key")
    func keySeparation() {
        let mask = PrivacyMask()
        mask.toggleIndividuallyHidden(label: "ab", value: "c")
        #expect(!mask.isIndividuallyHidden(label: "a", value: "bc"))
    }
}

@MainActor
@Suite("Settings", .serialized)
struct SettingsTests {
    let keys = [
        AppSettings.externalLookupsKey, AppSettings.externalPromptShownKey, AppSettings.onboardingShownKey,
        AppSettings.rateUnitKey,
    ]

    func withCleanDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let saved = keys.map { defaults.object(forKey: $0) }
        keys.forEach { defaults.removeObject(forKey: $0) }
        body()
        for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) }
    }

    @Test("A fresh install asks before anything goes to the internet")
    func defaultsAreOff() {
        withCleanDefaults {
            let settings = AppSettings()
            #expect(!settings.externalLookups)
            #expect(!settings.externalPromptShown)
            #expect(!settings.onboardingShown)
            #expect(settings.rateUnit == .megabitPerSecond)
        }
    }

    @Test("Every setting survives a relaunch")
    func persisted() {
        withCleanDefaults {
            let settings = AppSettings()
            settings.externalLookups = true
            settings.externalPromptShown = true
            settings.onboardingShown = true
            settings.rateUnit = .megabytePerSecond
            let again = AppSettings()
            #expect(again.externalLookups)
            #expect(again.externalPromptShown)
            #expect(again.onboardingShown)
            #expect(again.rateUnit == .megabytePerSecond)
        }
    }

    @Test("An unknown stored unit falls back to Mbit/s")
    func unknownUnit() {
        withCleanDefaults {
            UserDefaults.standard.set("furlongs", forKey: AppSettings.rateUnitKey)
            #expect(AppSettings().rateUnit == .megabitPerSecond)
        }
    }
}

@MainActor
@Suite("Navigation between tabs")
struct NavigationTests {
    @Test("A device in the LAN opens a tool with its address")
    func openTool() {
        let navigation = AppNavigation()
        navigation.tab = .lan
        navigation.open(.ports, target: "192.168.178.52")
        #expect(navigation.tab == .tools)
        #expect(navigation.toolRequest?.tool == .ports)
        #expect(navigation.toolRequest?.target == "192.168.178.52")
    }

    @Test("Two requests for the same tool and target are still two requests")
    func requestsAreDistinct() {
        #expect(ToolRequest(tool: .ping, target: "a") != ToolRequest(tool: .ping, target: "a"))
    }

    @Test("A page of the overview can be opened from another tab")
    func openOverview() {
        let navigation = AppNavigation()
        navigation.tab = .lan
        navigation.openOverview(.wifi)
        #expect(navigation.tab == .overview)
        #expect(navigation.overviewRequest == .wifi)
    }

    @Test("Every tool has a title and a unique raw value for the demo arguments")
    func tools() {
        #expect(Set(ToolKind.allCases.map(\.rawValue)).count == ToolKind.allCases.count)
        for tool in ToolKind.allCases { #expect(!String(localized: tool.title).isEmpty) }
    }

    @Test("Every tab has a raw value for -demo-tab")
    func tabs() {
        for name in ["overview", "lan", "live", "tools", "about"] { #expect(AppTab(rawValue: name) != nil) }
    }
}

@MainActor
@Suite("Tool input")
struct ToolModelTests {
    @Test("Start needs something other than spaces")
    func canStart() {
        let ping = PingModel()
        #expect(!ping.canStart)
        ping.input = "   "
        #expect(!ping.canStart)
        ping.input = " 1.1.1.1 "
        #expect(ping.canStart)
        let models: [any ToolControl] = [TracerouteModel(), DNSModel(), WhoisModel(), TLSModel(), HTTPModel(), DualStackModel()]
        for model in models { #expect(!model.canStart) }
    }

    @Test("NTP and NAT start without input: their own server is optional")
    func optionalServer() {
        #expect(NTPModel().canStart)
        #expect(NATModel().canStart)
    }

    @Test("An invalid own server or host is turned down and nothing starts", arguments: ["keinhost!!!", "a b", "host:99999", "host:abc"])
    func invalidServer(_ input: String) {
        let nat = NATModel()
        nat.customServer = input
        nat.start()
        #expect(!nat.isRunning)
        #expect(nat.failure != nil, "NAT took “\(input)”")
        nat.stop()

        let dualstack = DualStackModel()
        dualstack.input = input
        dualstack.start()
        #expect(!dualstack.isRunning)
        #expect(dualstack.failure != nil, "Dual stack took “\(input)”")
        dualstack.stop()

        if !input.contains(":") {
            let ntp = NTPModel()
            ntp.customServer = input
            ntp.start()
            #expect(!ntp.isRunning)
            #expect(ntp.failure != nil, "NTP took “\(input)”")
            ntp.stop()
        }
    }

    @Test("The demos of the new tools have a result")
    func newToolDemos() {
        #expect(NATModel.demo().report != nil)
        #expect(!NTPModel.demo().rows.isEmpty)
        #expect(DualStackModel.demo().report != nil)
    }

    @Test("An invalid host is turned down at once and nothing starts", arguments: ["keinhost!!!", "a b", "http://", "-x"])
    func invalidHost(_ input: String) {
        let ping = PingModel()
        ping.input = input
        ping.start()
        #expect(!ping.isRunning)
        #expect(ping.failure != nil)
    }

    @Test("A payload out of range is turned down before the ping starts")
    func invalidPayload() {
        let ping = PingModel()
        ping.input = "127.0.0.1"
        ping.payloadText = "999999"
        ping.start()
        #expect(!ping.isRunning)
        #expect(ping.failure != nil)
    }

    @Test("The packet size sets the payload: 28 bytes of header on IPv4")
    func packetSize() {
        let ping = PingModel()
        ping.setPacketSize(1500)
        #expect(ping.payloadText == "1472")
        #expect(ping.packetSizeText?.contains("1500") == true)
    }

    @Test("The family choice only appears when the name has both")
    func familyChoice() {
        #expect(!PingModel().offersFamilyChoice)
        #expect(PingModel.demo().offersFamilyChoice)
    }

    @Test("Ports: a local target needs common ports or a list")
    func portsCanStart() {
        let ports = PortsModel()
        ports.input = "192.168.178.1"
        #expect(ports.canStart)
        ports.useCommonPorts = false
        #expect(!ports.canStart)
        ports.portsText = "22,80"
        #expect(ports.canStart)
        ports.portsText = "  "
        #expect(!ports.canStart)
    }

    @Test("DNS: the system resolver only without encryption")
    func dnsSystem() {
        let dns = DNSModel()
        dns.systemServers = ["192.168.178.1"]
        #expect(dns.offersSystem)
        #expect(dns.endpoint(for: .system) != nil)
        dns.encryption = .tls
        #expect(!dns.offersSystem)
        #expect(dns.endpoint(for: .system) == nil)
        #expect(dns.choice == .cloudflare, "Switching on encryption moves away from the system resolver")
    }

    @Test("DNS: without system servers there is no system endpoint")
    func dnsNoSystem() {
        let dns = DNSModel()
        #expect(dns.endpoint(for: .system) == nil)
    }

    @Test("DNS: every public server is reachable in every encryption", arguments: DNSEncryption.allCases)
    func dnsPublic(_ encryption: DNSEncryption) {
        let dns = DNSModel()
        dns.encryption = encryption
        for choice in [DNSServerChoice.cloudflare, .google, .quad9] {
            #expect(dns.endpoint(for: choice) != nil, "\(choice) with \(encryption)")
        }
    }

    @Test("DNS: a typed server is only used when it is valid")
    func dnsCustom() {
        let dns = DNSModel()
        #expect(dns.endpoint(for: .custom) == nil)
        dns.customServer = "not an address"
        #expect(dns.endpoint(for: .custom) == nil)
        dns.customServer = " 9.9.9.11 "
        #expect(dns.endpoint(for: .custom) != nil)
    }

    @Test("DNS: no verdict on agreement before two answers")
    func dnsComparison() {
        #expect(DNSModel().comparisonAgrees == nil)
    }

    @Test("Every demo model has a result on screen", arguments: 0..<7)
    func demos(_ index: Int) {
        let demos: [any ToolControl] = [
            PingModel.demo(), TracerouteModel.demo(), DNSModel.demo(), WhoisModel.demo(), PortsModel.demo(),
            TLSModel.demo(), HTTPModel.demo(),
        ]
        let model = demos[index]
        #expect(!model.inputText.isEmpty)
        #expect(!model.isRunning)
        #expect(model.failure == nil)
    }

    @Test("Stop on a model that is not running changes nothing")
    func stopIdle() {
        let models: [any ToolControl] = [PingModel(), TracerouteModel(), DNSModel(), WhoisModel(), PortsModel(), TLSModel(), HTTPModel()]
        for model in models {
            model.stop()
            #expect(!model.isRunning)
        }
    }
}

@MainActor
@Suite("Demo data")
struct DemoTests {
    @Test("The demo LAN lists every device once, this iPhone and the router included")
    func lan() async {
        let lan = LANModel(isDemo: true)
        let snapshot = DemoData.snapshot
        lan.start(snapshot)
        for _ in 0..<50 where lan.phase != .finished { try? await Task.sleep(for: .milliseconds(100)) }
        #expect(lan.phase == .finished)
        let devices = lan.devices(thisDevice: snapshot.primaryIPv4?.ip, gateway: snapshot.localGateway4)
        let ips = devices.map(\.ip)
        #expect(Set(ips).count == ips.count, "A device is listed twice")
        for ip in ["192.168.178.1", "192.168.178.40", "192.168.178.52", "192.168.178.60"] {
            #expect(ips.contains(ip), "\(ip) is missing")
        }
    }

    @Test("Live offers the connections of the demo snapshot")
    func live() {
        let live = LiveModel(isDemo: true)
        let interfaces = live.interfaces(in: DemoData.snapshot)
        #expect(!interfaces.isEmpty)
        #expect(Set(interfaces.map(\.name)).count == interfaces.count)
        #expect(live.selected(in: DemoData.snapshot) != nil)
    }
}
