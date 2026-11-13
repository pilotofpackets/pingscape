import Foundation
import NetKit
import Testing

@testable import Pingscape

@MainActor
@Suite("Recent targets")
struct ToolHistoryTests {
    @Test("The newest target comes first, without duplicates, trimmed")
    func order() {
        let history = ToolHistory()
        history.remember("1.1.1.1", for: .ping)
        history.remember("example.com", for: .ping)
        history.remember("  1.1.1.1 \n", for: .ping)
        #expect(history.recent(.ping) == ["1.1.1.1", "example.com"])
    }

    @Test("At most five targets are kept, the oldest falls out")
    func capacity() {
        let history = ToolHistory()
        for index in 1...7 { history.remember("host\(index)", for: .dns) }
        #expect(history.recent(.dns) == ["host7", "host6", "host5", "host4", "host3"])
    }

    @Test("Every tool has its own list")
    func perTool() {
        let history = ToolHistory()
        history.remember("a", for: .ping)
        history.remember("b", for: .whois)
        #expect(history.recent(.ping) == ["a"])
        #expect(history.recent(.whois) == ["b"])
        #expect(history.recent(.tls).isEmpty)
    }

    @Test("Empty input is not remembered, and a target can be forgotten")
    func emptyAndForget() {
        let history = ToolHistory()
        history.remember("   ", for: .ping)
        #expect(history.recent(.ping).isEmpty)
        history.remember("gone.example", for: .ping)
        history.remember("stays.example", for: .ping)
        history.forget(" gone.example ", for: .ping)
        #expect(history.recent(.ping) == ["stays.example"])
        history.forget("never-there", for: .traceroute)
        #expect(history.recent(.traceroute).isEmpty)
    }
}

@MainActor
@Suite("LAN search state", .serialized)
struct LANModelTests {
    @Test("This device is listed first even when it did not answer")
    func thisDeviceFirst() {
        let lan = LANModel(isDemo: true)
        let devices = lan.devices(thisDevice: "192.168.178.42", gateway: "192.168.178.1")
        #expect(devices.map(\.ip) == ["192.168.178.42"])
        #expect(lan.devices(thisDevice: nil, gateway: nil).isEmpty)
    }

    @Test("The demo search lists this device, the router, then by address")
    func order() async {
        let lan = LANModel(isDemo: true)
        let snapshot = DemoData.snapshot
        lan.start(snapshot)
        for _ in 0..<50 where lan.phase != .finished { try? await Task.sleep(for: .milliseconds(100)) }
        let ips = lan.devices(thisDevice: snapshot.primaryIPv4?.ip, gateway: snapshot.localGateway4).map(\.ip)
        #expect(ips.first == "192.168.178.42")
        #expect(ips.dropFirst().first == "192.168.178.1")
        let rest = Array(ips.dropFirst(2))
        #expect(rest == rest.sorted { (IPv4.toInt($0) ?? 0) < (IPv4.toInt($1) ?? 0) }, "Not sorted by address: \(rest)")
        #expect(lan.finishedAt != nil)
        #expect(!lan.isBusy)
    }

    @Test("Stop while searching marks the search as interrupted; stop when idle does nothing")
    func stop() {
        let lan = LANModel(isDemo: true)
        lan.stop()
        #expect(lan.phase == .idle)
        lan.start(DemoData.snapshot)
        if lan.isBusy {
            lan.stop()
            #expect(lan.phase == .interrupted)
        }
    }

    @Test("A snapshot without a local network starts nothing")
    func noNetwork() {
        let lan = LANModel(isDemo: true)
        var snapshot = DemoData.snapshot
        snapshot.interfaces = []
        lan.start(snapshot)
        #expect(lan.phase == .idle)
    }
}

@MainActor
@Suite("Live", .serialized)
struct LiveModelTests {
    @Test("A pick that exists wins, an unknown pick falls back to the active route")
    func pick() {
        let live = LiveModel(isDemo: true)
        let snapshot = DemoData.snapshot
        let names = live.interfaces(in: snapshot).map(\.name)
        guard let other = names.last else {
            Issue.record("No interfaces in the demo snapshot")
            return
        }
        live.picked = other
        #expect(live.selected(in: snapshot)?.name == other)
        live.picked = "nonexistent0"
        let carrying = snapshot.defaultRoutes.first(where: \.isActive)?.interfaceName
        #expect(live.selected(in: snapshot)?.name == (names.contains(carrying ?? "") ? carrying : names.first))
    }

    @Test("Only Wi-Fi and cable have a router to ping")
    func gateway() {
        let live = LiveModel(isDemo: true)
        let snapshot = DemoData.snapshot
        for interface in live.interfaces(in: snapshot) {
            let target = live.gatewayTarget(in: snapshot, interface: interface)
            let kind = snapshot.interfaces.first { $0.name == interface.name }?.kind
            if kind == .wifi {
                #expect(target == "192.168.178.1", "\(interface.name)")
            } else if kind != .ethernet {
                #expect(target == nil, "\(interface.name) (\(String(describing: kind))) should have no router target")
            }
        }
        #expect(live.gatewayTarget(in: snapshot, interface: nil) == nil)
    }

    @Test("Cellular is offered once, tunnels with their name")
    func offered() {
        let live = LiveModel(isDemo: true)
        let titles = live.interfaces(in: DemoData.snapshot).map(\.title)
        #expect(titles.filter { $0 == String(localized: "Cellular") }.count <= 1)
        #expect(titles.contains(String(localized: "Wi-Fi")))
        #expect(titles.contains { $0.hasPrefix("VPN utun") })
        #expect(!titles.contains { $0.contains("lo0") || $0.contains("awdl") }, "Loopback and AWDL are not offered")
    }

    @Test("The demo has data on every chart")
    func demo() {
        let live = LiveModel(isDemo: true)
        #expect(!live.receive.isEmpty)
        #expect(!live.send.isEmpty)
        #expect(!live.latencyPoints.isEmpty)
    }
}
