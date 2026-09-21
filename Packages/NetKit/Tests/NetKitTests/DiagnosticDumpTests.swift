import CryptoKit
import Foundation
import Testing

@testable import NetKit

@Suite("Snapshot anonymizer")
struct AnonymizerTests {
    private let key = SymmetricKey(data: Data(repeating: 7, count: 32))

    private func address(_ ip: String, prefix: Int, v6: Bool = false) -> InterfaceAddress {
        InterfaceAddress(ip: ip, isIPv6: v6, prefixLength: prefix, netmask: v6 ? nil : IPv4.netmask(fromPrefix: prefix))
    }

    /// Wi-Fi with a full-tunnel WireGuard VPN, a cellular link and the system tunnels.
    private var scenario: NetworkSnapshot {
        NetworkSnapshot(
            path: PathSummary(isOnline: true, gateways: ["192.168.178.1"]),
            interfaces: [
                NetworkInterface(name: "lo0", addresses: [address("127.0.0.1", prefix: 8), address("::1", prefix: 128, v6: true)]),
                NetworkInterface(
                    name: "en0",
                    addresses: [
                        address("192.168.178.42", prefix: 24),
                        address("2001:db8:4a1c:9e00:18c7:59b8:cdc:db7c", prefix: 64, v6: true),
                        address("fe80::1c3a:52ff:fe91:7d40", prefix: 64, v6: true),
                        address("fd12:3456:789a::42", prefix: 64, v6: true),
                    ]),
                NetworkInterface(name: "pdp_ip0", addresses: [address("100.72.31.14", prefix: 30)]),
                NetworkInterface(name: "utun2", addresses: [address("fe80::6a1d:c0a3:5f2e:11b8", prefix: 64, v6: true)]),
                NetworkInterface(name: "utun4", addresses: [address("10.250.10.1", prefix: 32)]),
                NetworkInterface(name: "awdl0", addresses: [address("169.254.10.20", prefix: 16)]),
            ],
            defaultRoutes: [
                DefaultRoute(interfaceName: "en0", gateway: "192.168.178.1", isActive: false),
                DefaultRoute(interfaceName: "en0", gateway: "fe80::1", isIPv6: true, isActive: false),
                DefaultRoute(interfaceName: "utun4", gateway: nil, isActive: true),
            ],
            dnsServers: ["10.250.10.1", "1.1.1.1", "2606:4700:4700::1111"],
            proxy: ProxyInfo(isEnabled: true, host: "proxy.corp.example", port: 8080, pacURL: "https://intranet.corp/pac.js"),
            vpnServiceInterfaces: ["utun4"],
            wifi: .value(WiFiInfo(ssid: "HomeNet", bssid: "3C:A6:2F:1B:D3:22", security: .personal, didAutoJoin: true)),
            cellularServices: [CellularService(id: "0000000100000001", isDataService: true, technology: .nrNonStandalone)],
            publicIPv4: .value("203.0.113.57"))
    }

    private func anonymized(_ snapshot: NetworkSnapshot) -> NetworkSnapshot {
        var anonymizer = SnapshotAnonymizer(key: key)
        return anonymizer.anonymize(snapshot)
    }

    @Test func givesTheSameDerivedAnswerAsTheOriginal() {
        let original = scenario
        let result = anonymized(original)
        #expect(result.isVPNActive == original.isVPNActive)
        #expect(result.vpnInterfaces.map(\.name) == original.vpnInterfaces.map(\.name))
        #expect(result.tunnelScope == original.tunnelScope)
        #expect(result.primaryInterface?.name == original.primaryInterface?.name)
        #expect(result.connectionKind == original.connectionKind)
        #expect(result.lanRange?.prefix == original.lanRange?.prefix)
        #expect(result.defaultRoutes.map(\.isActive) == original.defaultRoutes.map(\.isActive))
        #expect(result.defaultRoutes.map(\.interfaceName) == original.defaultRoutes.map(\.interfaceName))
    }

    @Test func keepsTheUsabilityOfEveryAddress() {
        let original = scenario
        let result = anonymized(original)
        for (before, after) in zip(original.interfaces, result.interfaces) {
            #expect(before.addresses.map(\.isUsable) == after.addresses.map(\.isUsable), "\(before.name)")
            #expect(before.addresses.map(\.prefixLength) == after.addresses.map(\.prefixLength))
            #expect(before.addresses.map(\.isIPv6) == after.addresses.map(\.isIPv6))
        }
    }

    @Test func replacesEveryAddressAndName() throws {
        let result = anonymized(scenario)
        let en0 = try #require(result.interfaces.first { $0.name == "en0" })
        #expect(en0.addresses[0].ip != "192.168.178.42")
        #expect(en0.addresses[1].ip != "2001:db8:4a1c:9e00:18c7:59b8:cdc:db7c")
        #expect(en0.addresses[2].ip != "fe80::1c3a:52ff:fe91:7d40")
        #expect(result.dnsServers.allSatisfy { !["10.250.10.1", "1.1.1.1", "2606:4700:4700::1111"].contains($0) } || result.dnsServers[0].hasPrefix("10."))
        #expect(result.dnsServers[1] != "1.1.1.1")
        #expect(result.wifi.value?.ssid == "Network")
        #expect(result.wifi.value?.bssid != "3C:A6:2F:1B:D3:22")
        #expect(result.proxy.host == "proxy.example")
        #expect(result.proxy.pacURL == "https://proxy.example/proxy.pac")
        #expect(result.proxy.port == 8080)
        #expect(result.cellularServices.map(\.id) == ["service-1"])
        #expect(result.cellularServices[0].isDataService)
        #expect(result.publicIPv4 == .none)
    }

    @Test func keepsAddressClassesAndTheirNetworks() throws {
        let result = anonymized(scenario)
        let en0 = try #require(result.interfaces.first { $0.name == "en0" })
        // Private stays private, in the same /16.
        #expect(en0.addresses[0].ip.hasPrefix("192.168."))
        #expect(en0.addresses[2].ip.hasPrefix("fe80:"))
        #expect(en0.addresses[3].ip.hasPrefix("fd"))
        #expect(en0.addresses[1].ip.first == "2" || en0.addresses[1].ip.first == "3")
        let cellular = try #require(result.interfaces.first { $0.name == "pdp_ip0" })
        let cgnat = try #require(IPv4.toInt(cellular.addresses[0].ip))
        #expect(cgnat >> 22 == IPv4.toInt("100.64.0.0")! >> 22)
        // Loopback is untouched.
        #expect(result.interfaces[0].addresses.map(\.ip) == ["127.0.0.1", "::1"])
        #expect(result.interfaces.first { $0.name == "awdl0" }?.addresses[0].ip.hasPrefix("169.254.") == true)
    }

    @Test func keepsTheGatewayInsideTheNetworkOfItsInterface() throws {
        let result = anonymized(scenario)
        let en0 = try #require(result.interfaces.first { $0.name == "en0" })
        let gateway = try #require(result.defaultRoutes.first { $0.interfaceName == "en0" && !$0.isIPv6 }?.gateway)
        let range = try #require(IPv4Range(ip: en0.addresses[0].ip, prefix: 24))
        #expect(IPv4Range(ip: gateway, prefix: 24)?.network == range.network)
        #expect(gateway != "192.168.178.1")
        #expect(result.path?.gateways == [gateway])
        // The two addresses were one host apart and stay different.
        #expect(gateway != en0.addresses[0].ip)
    }

    @Test func mapsTheSameAddressToTheSameAddressEverywhere() {
        var anonymizer = SnapshotAnonymizer(key: key)
        #expect(anonymizer.ip("192.168.1.1") == anonymizer.ip("192.168.1.1"))
        #expect(anonymizer.ip("192.168.1.1") != anonymizer.ip("192.168.1.2"))
        #expect(anonymizer.ip("not an address") == "not an address")
    }

    @Test func aNewKeyGivesADifferentMapping() {
        var first = SnapshotAnonymizer(key: SymmetricKey(data: Data(repeating: 1, count: 32)))
        var second = SnapshotAnonymizer(key: SymmetricKey(data: Data(repeating: 2, count: 32)))
        #expect(first.ip("8.8.4.4") != second.ip("8.8.4.4") || first.ip("192.168.77.9") != second.ip("192.168.77.9"))
    }

    @Test func publicAddressesStayPublic() {
        var anonymizer = SnapshotAnonymizer(key: key)
        for text in ["1.1.1.1", "8.8.8.8", "93.184.216.34", "203.0.113.57", "9.9.9.9"] {
            let mapped = anonymizer.ip(text)
            let octets = mapped.split(separator: ".").compactMap { Int($0) }
            #expect(octets.count == 4)
            #expect(octets[0] != 0 && octets[0] != 10 && octets[0] != 127 && octets[0] < 224, "\(text) -> \(mapped)")
            #expect(!(octets[0] == 192 && octets[1] == 168), "\(text) -> \(mapped)")
            #expect(!(octets[0] == 172 && (16...31).contains(octets[1])), "\(text) -> \(mapped)")
            #expect(!(octets[0] == 169 && octets[1] == 254), "\(text) -> \(mapped)")
            #expect(!(octets[0] == 100 && (64...127).contains(octets[1])), "\(text) -> \(mapped)")
        }
    }

    @Test func keepsTheVendorPrefixOfAMACAddress() {
        var anonymizer = SnapshotAnonymizer(key: key)
        let mapped = anonymizer.mac("3C:A6:2F:1B:D3:22")
        #expect(mapped.hasPrefix("3C:A6:2F:"))
        #expect(mapped != "3C:A6:2F:1B:D3:22")
        #expect(anonymizer.mac("junk") == "junk")
    }
}

@Suite("Diagnostic dump")
struct DiagnosticDumpTests {
    private let app = DiagnosticDump.App(version: "1.0", build: "12")
    private let device = DiagnosticDump.Device(model: "iPhone17,3", os: "26.0")

    @Test func roundTripsThroughJSON() throws {
        let dump = DiagnosticDump(
            snapshot: DemoData.snapshot, app: app, device: device, anonymize: false,
            takenAt: Date(timeIntervalSince1970: 1_789_900_000))
        let decoded = try DiagnosticDump.decode(try dump.json())
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.app == app && decoded.device == device)
        #expect(decoded.snapshot.interfaces == DemoData.snapshot.interfaces)
        #expect(decoded.snapshot.defaultRoutes == DemoData.snapshot.defaultRoutes)
        #expect(decoded.snapshot.wifi == DemoData.snapshot.wifi)
        #expect(decoded.snapshot.cellularServices == DemoData.snapshot.cellularServices)
        #expect(decoded.snapshot.isVPNActive && decoded.snapshot.tunnelScope == .full)
        #expect(decoded.derived.isVPN && decoded.derived.tunnelScope == "full")
        #expect(decoded.derived.vpnInterfaces == ["utun4"])
        #expect(decoded.derived.carriesTrafficThroughTunnel)
        #expect(!decoded.anonymized)
    }

    @Test func leavesOutExternalValues() throws {
        var snapshot = DemoData.snapshot
        snapshot.publicIPv4 = .value("203.0.113.57")
        snapshot.publicIPv6 = .value("2001:db8::57")
        let text = String(decoding: try DiagnosticDump(snapshot: snapshot, app: app, device: device, anonymize: false).json(), as: UTF8.self)
        #expect(!text.contains("203.0.113.57"))
        #expect(!text.contains("2001:db8::57"))
    }

    @Test func anonymizedDumpHoldsNoRealAddressOrName() throws {
        let text = String(decoding: try DiagnosticDump(snapshot: DemoData.snapshot, app: app, device: device, anonymize: true).json(), as: UTF8.self)
        for secret in ["192.168.178.42", "192.168.178.1", "HomeNet", "3C:A6:2F:1B:D3:22", "2001:db8:4a1c", "1c3a:52ff", "10.250.10.1"] {
            #expect(!text.contains(secret), "\(secret)")
        }
        #expect(text.contains("\"anonymized\" : true"))
    }

    @Test func anonymizedDumpStillDetectsTheVPN() throws {
        let dump = DiagnosticDump(snapshot: DemoData.snapshot, app: app, device: device, anonymize: true)
        let decoded = try DiagnosticDump.decode(try dump.json())
        #expect(decoded.snapshot.isVPNActive)
        #expect(decoded.snapshot.tunnelScope == .full)
        #expect(decoded.snapshot.vpnInterfaces.map(\.name) == ["utun4"])
        #expect(decoded.snapshot.primaryInterface?.name == "en0")
        #expect(decoded.snapshot.localGateway4 != nil)
    }

    @Test func readsADumpWithoutTheNewerPathFields() throws {
        let path = #"{"isOnline":true,"supportsIPv4":true,"supportsIPv6":true,"supportsDNS":true,"isExpensive":false,"isConstrained":false}"#
        let decoded = try JSONDecoder().decode(PathSummary.self, from: Data(path.utf8))
        #expect(decoded.gateways.isEmpty && decoded.unsatisfiedReason == nil)
    }

    @Test func encodesEveryAvailabilityCase() throws {
        let cases: [Availability<String>] = [.value("x"), .loading, .needsPermission(.location), .failed("no"), .none]
        for original in cases {
            let data = try JSONEncoder().encode(original)
            #expect(try JSONDecoder().decode(Availability<String>.self, from: data) == original)
        }
    }
}
