import Foundation

/// A fixed snapshot for demos, previews, screenshots and UI tests.
///
/// Addresses come from the ranges reserved for documentation (RFC 5737 and
/// RFC 3849), except the private ones a home network really uses.
public enum DemoData {
    public static let snapshot = NetworkSnapshot(
        takenAt: Date(timeIntervalSince1970: 1_789_900_000),
        path: PathSummary(isOnline: true),
        interfaces: [
            NetworkInterface(
                name: "lo0", flags: [.up, .loopback, .running, .multicast], mtu: 16384,
                addresses: [
                    InterfaceAddress(ip: "127.0.0.1", isIPv6: false, prefixLength: 8),
                    InterfaceAddress(ip: "::1", isIPv6: true, prefixLength: 128),
                ],
                receivedBytes: 61_000_000, sentBytes: 61_000_000,
                receivedPackets: 152_000, sentPackets: 152_000),
            NetworkInterface(
                name: "en0", flags: [.up, .broadcast, .running, .simplex, .multicast], mtu: 1500,
                addresses: [
                    InterfaceAddress(
                        ip: "192.168.178.42", isIPv6: false, prefixLength: 24, netmask: "255.255.255.0"),
                    InterfaceAddress(
                        ip: "2001:db8:4a1c:9e00:18c7:59b8:cdc:db7c", isIPv6: true, prefixLength: 64),
                    InterfaceAddress(ip: "fe80::1c3a:52ff:fe91:7d40", isIPv6: true, prefixLength: 64),
                ],
                receivedBytes: 6_400_000_000, sentBytes: 380_000_000,
                receivedPackets: 5_120_000, sentPackets: 1_930_000),
            NetworkInterface(
                name: "awdl0", flags: [.up, .broadcast, .running, .simplex, .multicast], mtu: 1500,
                addresses: [InterfaceAddress(ip: "fe80::a4b2:1cff:fe08:6e13", isIPv6: true, prefixLength: 64)],
                receivedBytes: 1_400_000, sentBytes: 900_000,
                receivedPackets: 3_100, sentPackets: 2_700),
            NetworkInterface(
                name: "pdp_ip0", flags: [.up, .pointToPoint, .running, .multicast], mtu: 1450,
                addresses: [
                    InterfaceAddress(
                        ip: "100.72.31.14", isIPv6: false, prefixLength: 30, netmask: "255.255.255.252")
                ],
                receivedBytes: 3_400_000_000, sentBytes: 210_000_000,
                receivedPackets: 2_600_000, sentPackets: 1_100_000),
            NetworkInterface(
                name: "utun2", flags: [.up, .pointToPoint, .running, .multicast], mtu: 1380,
                addresses: [InterfaceAddress(ip: "fe80::6a1d:c0a3:5f2e:11b8", isIPv6: true, prefixLength: 64)],
                receivedBytes: 0, sentBytes: 4_100, receivedPackets: 0, sentPackets: 41),
            NetworkInterface(
                name: "utun4", flags: [.up, .pointToPoint, .running, .multicast], mtu: 1420,
                addresses: [
                    InterfaceAddress(
                        ip: "10.250.10.1", isIPv6: false, prefixLength: 32, netmask: "255.255.255.255")
                ],
                receivedBytes: 1_200_000_000, sentBytes: 88_000_000,
                receivedPackets: 812_000, sentPackets: 640_000),
        ],
        defaultRoutes: [
            DefaultRoute(interfaceName: "en0", gateway: "192.168.178.1", isIPv6: false, isActive: false),
            DefaultRoute(interfaceName: "utun4", gateway: nil, isIPv6: false, isActive: true),
        ],
        dnsServers: ["10.250.10.1"],
        proxy: ProxyInfo(),
        vpnServiceInterfaces: ["utun4"],
        wifi: .value(
            WiFiInfo(
                ssid: "HomeNet", bssid: "3C:A6:2F:1B:D3:22", security: .personal,
                didAutoJoin: true, didJustJoin: false)),
        cellularServices: [
            CellularService(id: "0000000100000001", isDataService: true, technology: .nrNonStandalone),
            CellularService(id: "0000000100000002", isDataService: false, technology: .lte),
        ])
}
