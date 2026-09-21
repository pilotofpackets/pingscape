#if DEBUG
import CoreLocation
import Foundation
import NetKit

/// A headless check for a real device, for the device tests in the test plan.
///
/// Launch with `-selftest` to print what the collectors and tools see, as
/// lines that start with `SELFTEST`. Add `-selftest-ask` to also trigger the
/// permission questions (location, local network) and to run the LAN search.
/// Addresses are never printed: only counts, families and whether an address
/// is local. Debug builds only.
@MainActor
enum SelfTest {
    static let isRequested = ProcessInfo.processInfo.arguments.contains("-selftest")
    private static let asks = ProcessInfo.processInfo.arguments.contains("-selftest-ask")

    private static func log(_ text: String) {
        NSLog("SELFTEST %@", text)
    }

    private static func timed<T>(_ work: () async -> T) async -> (T, Double) {
        let start = Date()
        let result = await work()
        return (result, Date().timeIntervalSince(start) * 1000)
    }

    static func run() async {
        log("begin \(DeviceInfo.modelIdentifier) iOS \(DeviceInfo.systemVersion) ask=\(asks)")
        log("location \(LocationAccess.state)")
        if asks, LocationAccess.state == .notDetermined {
            CLLocationManager().requestWhenInUseAuthorization()
            for _ in 0..<60 where LocationAccess.state == .notDetermined { try? await Task.sleep(for: .seconds(1)) }
            log("location after question \(LocationAccess.state)")
        }

        let provider = LiveSnapshotProvider(locationAuthorized: { LocationAccess.isAuthorized })
        let snapshot = await provider.snapshot()
        describe(snapshot)
        await network(snapshot)
        if asks { await localNetwork(snapshot) }
        log("intent status-text lines=\(StatusText.make(snapshot).split(separator: "\n").count) vpn=\(snapshot.isVPNActive)")
        await internet()
        log("end")
    }

    // MARK: What the collectors see

    private static func describe(_ snapshot: NetworkSnapshot) {
        if let path = snapshot.path {
            log("path online=\(path.isOnline) v4=\(path.supportsIPv4) v6=\(path.supportsIPv6) dns=\(path.supportsDNS) expensive=\(path.isExpensive) constrained=\(path.isConstrained) gateways=\(path.gateways.count) reason=\(path.unsatisfiedReason?.rawValue ?? "-")")
        } else {
            log("path none")
        }
        for interface in snapshot.interfaces {
            let counters = interface.receivedBytes.map { "rx=\($0) tx=\(interface.sentBytes ?? 0)" } ?? "counters=none"
            log("interface \(interface.name) kind=\(interface.kind.rawValue) up=\(interface.isUp) flags=\(interface.flags.names.joined(separator: ",")) mtu=\(interface.mtu ?? 0) v4=\(interface.ipv4Addresses.count) v6=\(interface.ipv6Addresses.count) usable=\(interface.hasUsableAddress) vpn=\(snapshot.isVPN(interface)) \(counters)")
        }
        for route in snapshot.defaultRoutes {
            log("default-route \(route.isIPv6 ? "v6" : "v4") via=\(route.interfaceName) active=\(route.isActive) gateway=\(route.gateway != nil)")
        }
        log("primary=\(snapshot.primaryInterface?.name ?? "-") vpn=\(snapshot.isVPNActive) scope=\(snapshot.tunnelScope.map { "\($0)" } ?? "-") serviceInterfaces=\(snapshot.vpnServiceInterfaces.sorted().joined(separator: ",")) gateway4=\(snapshot.localGateway4 != nil) lan=\(snapshot.lanRange?.description.split(separator: "/").last.map { "/\($0)" } ?? "-")")
        log("dns servers=\(snapshot.dnsServers.count) proxy=\(snapshot.proxy.isEnabled)")
        switch snapshot.wifi {
        case .value(let wifi):
            log("wifi value ssid=\(!wifi.ssid.isEmpty) bssid=\(wifi.bssid != nil) security=\(wifi.security.rawValue) autoJoin=\(String(describing: wifi.didAutoJoin)) justJoin=\(String(describing: wifi.didJustJoin))")
        case .needsPermission(let permission): log("wifi needsPermission \(permission)")
        case .loading: log("wifi loading")
        case .failed(let message): log("wifi failed \(message)")
        case .none: log("wifi none")
        }
        log("cellular services=\(snapshot.cellularServices.map { "\($0.isDataService ? "data" : "other"):\($0.technology.rawValue)" }.joined(separator: ",")) access=\(CellularDataAccess.current)")
        log("routes all=\(RouteCollector.allRoutes().count) nat64=\(NAT64Collector.prefix() ?? "-")")
    }

    // MARK: Tools without any permission

    private static func network(_ snapshot: NetworkSnapshot) async {
        if let gateway = snapshot.localGateway4, let address = ResolvedAddress(literal: gateway) {
            log("ping gateway (before any local network question) \(await pingSummary(address))")
            if let server = snapshot.dnsServers.first, let dns = ResolvedAddress(literal: server) {
                let (result, ms) = await timed { try? await DNSClient.query(name: "example.com", type: .a, server: dns) }
                log("dns system-server local=\(dns.isLocal) code=\(result?.responseCodeName ?? "error") answers=\(result?.answers.count ?? 0) \(Int(ms)) ms")
            }
            var opens: [String] = []
            for await event in PortScanner.run(address: address, ports: [53, 80, 443]) {
                if case .result(let port, let state, _) = event { opens.append("\(port)=\(state)") }
            }
            log("ports gateway \(opens.sorted().joined(separator: " "))")
        } else {
            log("no gateway for the local checks")
        }
        if let target = ResolvedAddress(literal: "1.1.1.1") {
            log("ping 1.1.1.1 \(await pingSummary(target))")
            var hops: [String] = []
            var settings = TracerouteSettings()
            settings.maximumHops = 4
            settings.probesPerHop = 1
            settings.timeoutSeconds = 1
            settings.resolveNames = false
            for await event in TracerouteTool.run(address: target, settings: settings) {
                switch event {
                case .hop(let hop):
                    let local = hop.address.flatMap(ResolvedAddress.init(literal:))?.isLocal
                    hops.append("\(hop.number):\(hop.address == nil ? "none" : (local == true ? "local" : "public")):\(hop.times.first.flatMap { $0 }.map { "\(Int($0))ms" } ?? "-")")
                case .failed(let error): hops.append("failed:\(error)")
                default: break
                }
            }
            log("traceroute \(hops.joined(separator: " "))")
        }
    }

    private static func pingSummary(_ address: ResolvedAddress) async -> String {
        var settings = PingSettings()
        settings.intervalSeconds = 0.3
        settings.timeoutSeconds = 1
        var lines: [String] = []
        var method = "?"
        for await event in PingTool.run(address: address, settings: settings) {
            switch event {
            case .started(_, let started): method = "\(started)"
            case .reply(_, _, let ms, _): lines.append("\(Int(ms.rounded()))ms")
            case .noReply: lines.append("noreply")
            case .failed(_, let error): lines.append("failed(\(error))")
            }
            if lines.count >= 3 { break }
        }
        return "method=\(method) \(lines.joined(separator: " "))"
    }

    // MARK: Local network (asks the user)

    private static func localNetwork(_ snapshot: NetworkSnapshot) async {
        let (access, ms) = await timed { await LocalNetworkPermission.check(timeoutSeconds: 60) }
        log("local-network permission=\(access) after \(Int(ms)) ms")
        if let gateway = snapshot.localGateway4, let address = ResolvedAddress(literal: gateway) {
            log("ping gateway (after) \(await pingSummary(address))")
            let info = await UPnPClient.describe(gateway: gateway)
            log("upnp router=\(info != nil) manufacturer=\(info?.manufacturer != nil) model=\(info?.model != nil) firmware=\(info?.firmware != nil) wan=\(info?.externalIP != nil) uptime=\(info?.uptimeSeconds != nil)")
        }
        var types: [String: Int] = [:]
        var ips = Set<String>()
        for await finding in BonjourBrowser.browse(duration: .seconds(6)) {
            types[finding.service.type, default: 0] += 1
            ips.insert(finding.ip)
        }
        log("bonjour services=\(types.values.reduce(0, +)) devices=\(ips.count) types=\(types.keys.sorted().joined(separator: ","))")
        guard let range = snapshot.lanRange, let me = snapshot.primaryIPv4?.ip else { return }
        for mode in [LANScanMode.quick, .thorough] {
            var list = LANDeviceList()
            let start = Date()
            for await event in LANScanner.run(range: range, thisDevice: me, mode: mode) { list.apply(event) }
            let devices = list.devices
            log("lan-search \(mode) devices=\(devices.count) ping=\(devices.filter(\.answeredPing).count) named=\(devices.filter { $0.displayName != nil }.count) hostnames=\(devices.filter { $0.hostname != nil }.count) macs=\(devices.filter { $0.macAddress != nil }.count) ports=\(devices.filter { !$0.openPorts.isEmpty }.count) \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        }
    }

    // MARK: Internet (App Transport Security, URLSession metrics, TLS)

    private static func internet() async {
        log("captive-probe \(await InternetCheck.run())")
        if let url = try? HTTPTimer.url(from: "https://example.com") {
            do {
                let steps = try await HTTPTimer.measure(url)
                log("http-timing https ok steps=\(steps.count) status=\(steps.last?.statusCode ?? 0) protocol=\(steps.last?.networkProtocol ?? "-") dns=\(steps.last?.dnsMilliseconds != nil) tcp=\(steps.last?.tcpMilliseconds != nil) tls=\(steps.last?.tlsMilliseconds != nil)")
            } catch { log("http-timing https failed \(error)") }
        }
        if let url = try? HTTPTimer.url(from: "http://example.com") {
            do {
                _ = try await HTTPTimer.measure(url)
                log("http-timing plain http to an internet host worked (unexpected)")
            } catch { log("http-timing plain http to an internet host -> \(error) (expected insecureConnection)") }
        }
        do {
            let report = try await TLSInspector.inspect(host: "example.com")
            log("tls ok protocol=\(report.protocolVersion ?? "-") chain=\(report.chain.count) trust=\(report.trust) days=\(report.chain.first?.daysUntilExpiry() ?? 0)")
        } catch { log("tls failed \(error)") }
    }
}
#endif
