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

    /// The longest values a real network gives: a 32-byte network name
    /// without a space, full-length IPv6 addresses, five DNS servers, two VPN
    /// tunnels, a proxy with a long PAC address and two SIMs. For checking
    /// that every page still lays out, at every text size.
    public static let longValues = NetworkSnapshot(
        takenAt: Date(timeIntervalSince1970: 1_789_900_000),
        path: PathSummary(isOnline: true, isExpensive: true, isConstrained: true),
        interfaces: [
            NetworkInterface(
                name: "lo0", flags: [.up, .loopback, .running, .multicast], mtu: 16384,
                addresses: [InterfaceAddress(ip: "127.0.0.1", isIPv6: false, prefixLength: 8)],
                receivedBytes: 61_000_000, sentBytes: 61_000_000,
                receivedPackets: 152_000, sentPackets: 152_000),
            NetworkInterface(
                name: "en0", flags: [.up, .broadcast, .running, .simplex, .multicast], mtu: 9000,
                addresses: [
                    InterfaceAddress(
                        ip: "172.31.255.254", isIPv6: false, prefixLength: 20, netmask: "255.255.240.0"),
                    InterfaceAddress(
                        ip: "2001:db8:ffff:ffff:ffff:ffff:ffff:fffe", isIPv6: true, prefixLength: 64),
                    InterfaceAddress(
                        ip: "2001:db8:ffff:ffff:a4b2:1cff:fe08:6e13", isIPv6: true, prefixLength: 64),
                    InterfaceAddress(ip: "fe80::ffff:ffff:ffff:fffe", isIPv6: true, prefixLength: 64),
                ],
                receivedBytes: 987_654_321_098, sentBytes: 123_456_789_012,
                receivedPackets: 999_888_777, sentPackets: 111_222_333),
            NetworkInterface(
                name: "pdp_ip0", flags: [.up, .pointToPoint, .running, .multicast], mtu: 1450,
                addresses: [
                    InterfaceAddress(
                        ip: "100.127.255.254", isIPv6: false, prefixLength: 30, netmask: "255.255.255.252"),
                    InterfaceAddress(
                        ip: "2001:db8:eeee:eeee:eeee:eeee:eeee:eeee", isIPv6: true, prefixLength: 64),
                ],
                receivedBytes: 45_600_000_000, sentBytes: 3_210_000_000,
                receivedPackets: 34_000_000, sentPackets: 9_800_000),
            NetworkInterface(
                name: "pdp_ip1", flags: [.up, .pointToPoint, .running, .multicast], mtu: 1500,
                addresses: [
                    InterfaceAddress(
                        ip: "100.64.0.1", isIPv6: false, prefixLength: 30, netmask: "255.255.255.252")
                ],
                receivedBytes: 1_000, sentBytes: 1_000, receivedPackets: 10, sentPackets: 10),
            NetworkInterface(
                name: "utun4", flags: [.up, .pointToPoint, .running, .multicast], mtu: 1280,
                addresses: [
                    InterfaceAddress(
                        ip: "10.255.255.254", isIPv6: false, prefixLength: 32, netmask: "255.255.255.255"),
                    InterfaceAddress(
                        ip: "fd00:ffff:ffff:ffff:ffff:ffff:ffff:fffe", isIPv6: true, prefixLength: 128),
                ],
                receivedBytes: 12_000_000_000, sentBytes: 880_000_000,
                receivedPackets: 8_120_000, sentPackets: 6_400_000),
            NetworkInterface(
                name: "utun12", flags: [.up, .pointToPoint, .running, .multicast], mtu: 1400,
                addresses: [
                    InterfaceAddress(
                        ip: "192.168.255.254", isIPv6: false, prefixLength: 32, netmask: "255.255.255.255")
                ],
                receivedBytes: 4_000, sentBytes: 4_000, receivedPackets: 40, sentPackets: 40),
        ],
        defaultRoutes: [
            DefaultRoute(interfaceName: "en0", gateway: "172.31.240.1", isIPv6: false, isActive: false),
            DefaultRoute(interfaceName: "en0", gateway: "fe80::ffff:ffff:ffff:1", isIPv6: true, isActive: false),
            DefaultRoute(interfaceName: "utun4", gateway: nil, isIPv6: false, isActive: true),
            DefaultRoute(interfaceName: "utun4", gateway: nil, isIPv6: true, isActive: true),
        ],
        dnsServers: [
            "2001:db8:ffff:ffff:ffff:ffff:ffff:fff1", "2001:db8:ffff:ffff:ffff:ffff:ffff:fff2",
            "10.255.255.254", "172.31.240.1", "100.100.100.100",
        ],
        proxy: ProxyInfo(
            isEnabled: true, host: "proxy.internal.department.example.com", port: 65535,
            pacURL: "https://wpad.internal.department.example.com/configuration/proxy-auto-config.pac"),
        vpnServiceInterfaces: ["utun4", "utun12"],
        wifi: .value(
            WiFiInfo(
                ssid: "WLAN-Obergeschoss-5GHz-AX-Mesh-2", bssid: "FE:DC:BA:98:76:54", security: .enterprise,
                didAutoJoin: false, didJustJoin: true)),
        cellularServices: [
            CellularService(id: "0000000100000001", isDataService: true, technology: .nrNonStandalone),
            CellularService(id: "0000000100000002", isDataService: false, technology: .lte),
        ])
}
