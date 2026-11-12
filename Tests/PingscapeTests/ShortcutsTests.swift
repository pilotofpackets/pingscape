import Foundation
import NetKit
import Testing
import UIKit

@testable import Pingscape

/// The logic behind Siri, the Shortcuts actions and the widgets: which value
/// comes from where, what is hidden, and where a deep link goes.
@MainActor
@Suite("Shortcuts and widgets", .serialized)
struct ShortcutsTests {
    let demo = DemoData.snapshot

    @Test("Each value reads what the demo network holds")
    func valuesFromTheDemo() {
        func read(_ value: NetworkValue) -> [String]? { try? value.read(from: demo).get() }
        #expect(read(.localIPv4) == ["192.168.178.42"])
        #expect(read(.subnetMask) == ["255.255.255.0"])
        #expect(read(.dnsServers) == ["10.250.10.1"])
        #expect(read(.wifiName) == ["HomeNet"])
        #expect(read(.bssid) == ["3C:A6:2F:1B:D3:22"])
        #expect(read(.wifiSecurity) == ["WPA2/WPA3 Personal"])
        #expect(read(.vpnInterface) == ["utun4"])
        #expect(read(.vpnAddress) == ["10.250.10.1"])
        #expect(read(.vpn)?.count == 1)
        #expect(read(.connection)?.count == 1)
        #expect(read(.cellular)?.count == 1)
    }

    @Test("A network without the value says so, never an empty answer")
    func missingValues() {
        var empty = demo
        empty.interfaces = []
        empty.defaultRoutes = []
        empty.dnsServers = []
        empty.vpnServiceInterfaces = []
        empty.wifi = .none
        empty.cellularServices = []
        for value in [NetworkValue.localIPv4, .subnetMask, .localIPv6, .gateway, .gatewayIPv6, .dnsServers,
                      .wifiName, .bssid, .wifiSecurity, .vpnInterface, .vpnAddress, .cellular, .interface, .mtu] {
            #expect(value.read(from: empty) == .failure(.notPresent), "\(value)")
            #expect(!value.missingText.isEmpty)
        }
        // "Not active" is an answer, not a missing value.
        #expect((try? NetworkValue.vpn.read(from: empty).get())?.count == 1)
    }

    @Test("Without the location permission the Wi-Fi values ask for it")
    func wifiNeedsLocation() {
        var snapshot = demo
        snapshot.wifi = .needsPermission(.location)
        for value in [NetworkValue.wifiName, .bssid, .wifiSecurity] {
            #expect(value.read(from: snapshot) == .failure(.needsLocation), "\(value)")
        }
    }

    @Test("Every address, mask and network name is marked sensitive")
    func sensitiveValues() {
        // An address (IPv4, IPv6, with or without prefix), a MAC address or the network's name.
        let identifier = #"^([0-9]{1,3}\.){3}[0-9]{1,3}$|:.*:|^[0-9A-F]{2}(:[0-9A-F]{2}){5}$"#
        for value in NetworkValue.allCases {
            guard let items = try? value.read(from: demo).get() else { continue }
            let identifies = items.contains { $0 == "HomeNet" || $0.range(of: identifier, options: .regularExpression) != nil }
            if identifies {
                #expect(value.isSensitive, "\(value) shows \(items) but is not hidden with “Hide values”")
            }
        }
        // The subnet mask too: together with the address it tells the network.
        #expect(NetworkValue.subnetMask.isSensitive)
    }

    @Test("Siri says a placeholder for sensitive values only while “Hide values” is on")
    func spokenValues() {
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: PrivacyMask.hideByDefaultKey)
        defer { defaults.set(before, forKey: PrivacyMask.hideByDefaultKey) }

        defaults.set(true, forKey: PrivacyMask.hideByDefaultKey)
        #expect(IntentSupport.shown("192.168.178.42", sensitive: true) == PrivacyMask.placeholder)
        #expect(IntentSupport.shown("Wi-Fi", sensitive: false) == "Wi-Fi")
        defaults.set(false, forKey: PrivacyMask.hideByDefaultKey)
        #expect(IntentSupport.shown("192.168.178.42", sensitive: true) == "192.168.178.42")
    }

    @Test("The status text hides every identifier while “Hide values” is on")
    func statusText() {
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: PrivacyMask.hideByDefaultKey)
        defer { defaults.set(before, forKey: PrivacyMask.hideByDefaultKey) }
        let secrets = ["192.168.178.42", "255.255.255.0", "HomeNet", "3C:A6:2F:1B:D3:22", "2001:db8:4a1c", "10.250.10.1"]

        defaults.set(true, forKey: PrivacyMask.hideByDefaultKey)
        let hidden = StatusText.make(demo)
        for secret in secrets {
            #expect(!hidden.contains(secret), "The hidden status text shows \(secret)")
        }
        #expect(hidden.contains("utun4"), "The interface name is no identifier and stays")

        defaults.set(false, forKey: PrivacyMask.hideByDefaultKey)
        let shown = StatusText.make(demo)
        for secret in ["192.168.178.42", "255.255.255.0", "HomeNet", "3C:A6:2F:1B:D3:22"] {
            #expect(shown.contains(secret), "The status text leaves out \(secret)")
        }
    }

    @Test("Every page's deep link opens that page", arguments: AppPage.allCases)
    func deepLinks(_ page: AppPage) {
        #expect(AppPage(url: page.url) == page)
        #expect(page.url.scheme == AppPage.scheme)
    }

    @Test("Links to anything else open nothing")
    func foreignLinks() {
        for text in ["pingscape://", "pingscape://tools", "pingscape://tools/nothing", "pingscape://settings",
                     "https://pingscape.app/tools/ping", "other://ping"] {
            #expect(AppPage(url: URL(string: text)!) == nil, "\(text)")
        }
    }

    @Test("Every value, query and page has a name and an SF Symbol that exists")
    func namesAndSymbols() {
        for value in NetworkValue.allCases {
            #expect(NetworkValue.caseDisplayRepresentations[value] != nil, "\(value)")
            #expect(UIImage(systemName: value.symbol) != nil, "\(value): \(value.symbol)")
        }
        for query in NetworkQuery.allCases {
            #expect(NetworkQuery.caseDisplayRepresentations[query] != nil, "\(query)")
        }
        for page in AppPage.allCases {
            #expect(AppPage.caseDisplayRepresentations[page] != nil, "\(page)")
            #expect(UIImage(systemName: page.symbol) != nil, "\(page): \(page.symbol)")
        }
    }

    @Test("Each local query reads the widget's value of the same name")
    func queriesMatchValues() {
        let local = NetworkQuery.allCases.compactMap(\.local)
        #expect(Set(local) == Set(NetworkValue.allCases))
        #expect(NetworkQuery.allCases.filter { $0.local == nil } == [.publicIPv4, .publicIPv6, .provider])
    }
}
