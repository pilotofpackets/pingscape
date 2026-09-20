import Testing

@testable import NetKit

@Suite("VPN detection and primary interface")
struct VPNDetectionTests {
    private func address(_ ip: String, prefix: Int? = nil, v6: Bool = false) -> InterfaceAddress {
        InterfaceAddress(ip: ip, isIPv6: v6, prefixLength: prefix)
    }

    /// The system's own tunnels: present on every iPhone, link-local only.
    private var systemTunnels: [NetworkInterface] {
        (0...3).map { NetworkInterface(name: "utun\($0)", addresses: [address("fe80::\($0)", v6: true)]) }
    }

    private var wifi: NetworkInterface {
        NetworkInterface(name: "en0", addresses: [address("192.168.178.42", prefix: 24)])
    }

    private var cellular: NetworkInterface {
        NetworkInterface(name: "pdp_ip0", addresses: [address("100.72.31.14", prefix: 30)])
    }

    @Test func noVPNWhenOnlySystemTunnelsExist() {
        let snapshot = NetworkSnapshot(interfaces: [wifi] + systemTunnels)
        #expect(!snapshot.isVPNActive)
        #expect(snapshot.tunnelScope == nil)
    }

    @Test func detectsAFullTunnelWireGuardStyle() {
        let tunnel = NetworkInterface(name: "utun4", mtu: 1420, addresses: [address("10.250.10.1", prefix: 32)])
        let snapshot = NetworkSnapshot(
            interfaces: [wifi, tunnel] + systemTunnels,
            defaultRoutes: [
                DefaultRoute(interfaceName: "en0", gateway: "192.168.178.1", isActive: false),
                DefaultRoute(interfaceName: "utun4", gateway: nil, isActive: true),
            ])
        #expect(snapshot.vpnInterfaces.map(\.name) == ["utun4"])
        #expect(snapshot.tunnelScope == .full)
        // The Wi-Fi gateway stays visible while the VPN carries the traffic.
        #expect(snapshot.localGateway4 == "192.168.178.1")
        #expect(snapshot.primaryInterface?.name == "en0")
    }

    @Test func detectsASplitTunnel() {
        let tunnel = NetworkInterface(name: "utun4", addresses: [address("10.250.10.1", prefix: 32)])
        let snapshot = NetworkSnapshot(
            interfaces: [wifi, tunnel],
            defaultRoutes: [DefaultRoute(interfaceName: "en0", gateway: "192.168.178.1", isActive: true)])
        #expect(snapshot.isVPNActive)
        #expect(snapshot.tunnelScope == .partial)
    }

    @Test func doesNotCountTheCarrierIPsecTunnelAsVPN() {
        let carrier = NetworkInterface(name: "ipsec0", addresses: [address("10.20.30.40", prefix: 32)])
        let snapshot = NetworkSnapshot(interfaces: [wifi, carrier], vpnServiceInterfaces: [])
        #expect(!snapshot.isVPNActive)
    }

    @Test func countsAnIPsecInterfaceThatTheSystemListsAsAService() {
        let ikev2 = NetworkInterface(name: "ipsec0", addresses: [address("10.9.0.7", prefix: 32)])
        let snapshot = NetworkSnapshot(interfaces: [wifi, ikev2], vpnServiceInterfaces: ["ipsec0"])
        #expect(snapshot.isVPNActive)
        #expect(snapshot.vpnInterfaces.map(\.name) == ["ipsec0"])
    }

    @Test func countsSeveralTunnelsAtOnce() {
        let wireguard = NetworkInterface(name: "utun4", addresses: [address("10.250.10.1", prefix: 32)])
        let ikev2 = NetworkInterface(name: "ipsec0", addresses: [address("10.9.0.7", prefix: 32)])
        let snapshot = NetworkSnapshot(interfaces: [wifi, wireguard, ikev2], vpnServiceInterfaces: ["ipsec0"])
        #expect(snapshot.vpnInterfaces.count == 2)
    }

    @Test func ignoresADownTunnel() {
        let tunnel = NetworkInterface(name: "utun4", isUp: false, addresses: [address("10.250.10.1", prefix: 32)])
        #expect(!NetworkSnapshot(interfaces: [wifi, tunnel]).isVPNActive)
    }

    @Test func prefersWiFiOverCellular() {
        #expect(NetworkSnapshot(interfaces: [cellular, wifi]).primaryInterface?.name == "en0")
        #expect(NetworkSnapshot(interfaces: [cellular]).primaryInterface?.name == "pdp_ip0")
    }

    @Test func neverPicksATunnelOrHotspotAsPrimary() {
        let hotspot = NetworkInterface(name: "bridge100", addresses: [address("172.20.10.1", prefix: 28)])
        let tunnel = NetworkInterface(name: "utun4", addresses: [address("10.250.10.1", prefix: 32)])
        #expect(NetworkSnapshot(interfaces: [hotspot, tunnel]).primaryInterface == nil)
    }

    @Test func derivesTheLANRangeFromThePrimaryAddress() {
        let range = NetworkSnapshot(interfaces: [wifi]).lanRange
        #expect(range?.description == "192.168.178.0/24")
    }

    @Test func usesTheNetmaskWhenThePrefixIsMissing() {
        let adapter = NetworkInterface(
            name: "en0",
            addresses: [InterfaceAddress(ip: "10.10.18.234", isIPv6: false, netmask: "255.255.254.0")])
        #expect(NetworkSnapshot(interfaces: [adapter]).lanRange?.description == "10.10.18.0/23")
    }

    @Test func demoDataDescribesAVPNOverWiFi() {
        let snapshot = DemoData.snapshot
        #expect(snapshot.primaryInterface?.name == "en0")
        #expect(snapshot.tunnelScope == .full)
        #expect(snapshot.localGateway4 == "192.168.178.1")
    }
}

@Suite("Collectors on this machine")
struct CollectorSmokeTests {
    @Test func readsTheLoopbackInterface() {
        let loopback = InterfaceCollector.collect().first { $0.name == "lo0" }
        #expect(loopback?.kind == .loopback)
        #expect(loopback?.addresses.contains { $0.ip == "127.0.0.1" } == true)
    }

    @Test func routeAndDNSCollectorsDoNotCrash() {
        _ = RouteCollector.defaultRoutes()
        _ = DNSCollector.servers()
        _ = ProxyCollector.collect()
    }

    @Test func buildsALiveSnapshot() async {
        let snapshot = await LiveSnapshotProvider().snapshot()
        #expect(!snapshot.interfaces.isEmpty)
    }
}
