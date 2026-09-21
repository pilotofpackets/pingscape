import NetKit
import Observation
import SwiftUI

struct WiFiDetailView: View {
    @Environment(SnapshotStore.self) private var store
    @Environment(LANModel.self) private var lan
    @State private var measurement = RouterMeasurement()

    var body: some View {
        let snapshot = store.snapshot
        DetailPage(title: "Wi-Fi", isAvailable: snapshot.map(isAvailable) ?? true) {
            if let snapshot {
                network(snapshot)
                addresses(snapshot)
                routerConnection(snapshot)
                routerInfo
                if let interface = snapshot.interface(of: .wifi) {
                    TrafficSection(interface: interface)
                }
                history
            }
        }
        .task(id: snapshot?.localGateway4) {
            if let gateway = snapshot?.localGateway4 { await lan.loadRouterInfo(gateway: gateway) }
        }
    }

    private func isAvailable(_ snapshot: NetworkSnapshot) -> Bool {
        switch snapshot.wifi {
        case .value, .needsPermission: true
        default: snapshot.interface(of: .wifi) != nil
        }
    }

    @ViewBuilder
    private func network(_ snapshot: NetworkSnapshot) -> some View {
        switch snapshot.wifi {
        case .value(let info):
            InfoSection(title: "Network") {
                DataRow(label: "Name (SSID)", value: info.ssid, sensitive: true)
                if let bssid = info.bssid {
                    DataRow(label: "BSSID", value: bssid, monospaced: true, sensitive: true)
                    if let vendor = store.oui.vendor(forBSSID: bssid) {
                        DataRow(label: "Vendor", value: vendor)
                    }
                }
                if let security = info.security.label {
                    DataRow(label: "Security", value: security)
                }
                if let autoJoined = info.didAutoJoin {
                    DataRow(label: "Joined automatically", value: yesNo(autoJoined))
                }
            }
        case .needsPermission:
            InfoSection(title: "Network") {
                WiFiPermissionPrompt()
            }
        case .loading, .failed, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func addresses(_ snapshot: NetworkSnapshot) -> some View {
        if let wifi = snapshot.interface(of: .wifi) {
            InfoSection(title: "Addresses") {
                Rows.addresses(of: wifi, gateway: snapshot.gateway(of: wifi))
                // The DNS servers belong to the system, not to Wi-Fi. While a
                // VPN is active they are usually the tunnel's, so they stay
                // off this page then.
                if !snapshot.isVPNActive {
                    Rows.dnsServers(snapshot.dnsServers)
                }
            }
        }
    }

    /// A short measurement to the router, on a tap.
    @ViewBuilder
    private func routerConnection(_ snapshot: NetworkSnapshot) -> some View {
        if let wifi = snapshot.interface(of: .wifi), let gateway = snapshot.gateway(of: wifi) {
            InfoSection(title: "Connection to router") {
                if let result = measurement.result {
                    DataRow(label: "Latency · Jitter · Loss", value: result)
                } else if let error = measurement.error {
                    DataRow(label: "Latency · Jitter · Loss", value: error.text)
                }
                if measurement.isRunning {
                    LoadingRow(label: "Measuring")
                } else {
                    PermissionRow(label: "Router", buttonTitle: "Measure") { measurement.start(gateway: gateway) }
                }
            }
        }
    }

    /// What the router says about itself over UPnP, only the fields it gives.
    @ViewBuilder
    private var routerInfo: some View {
        if let info = lan.routerInfo {
            InfoSection(title: "Router (UPnP)") {
                if let manufacturer = info.manufacturer { DataRow(label: "Manufacturer", value: manufacturer) }
                if let model = info.model { DataRow(label: "Model", value: model) }
                if let firmware = info.firmware { DataRow(label: "Firmware", value: firmware) }
                if let externalIP = info.externalIP {
                    DataRow(label: "WAN address", value: externalIP, monospaced: true, sensitive: true)
                }
                if let uptime = info.uptimeSeconds {
                    DataRow(label: "Uptime", value: Duration.seconds(uptime).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))
                }
            }
        }
    }

    /// Access point changes seen while the app was open.
    @ViewBuilder
    private var history: some View {
        let changes = store.timeline.bssidChanges
        if !changes.isEmpty {
            InfoSection(title: "History (this session)") {
                ForEach(changes) { entry in
                    if case .bssid(let from, let to) = entry.change {
                        DataRow(
                            label: LocalizedStringResource(stringLiteral: entry.time.formatted(date: .omitted, time: .shortened)),
                            value: "\(from) → \(to)", monospaced: true, sensitive: true, stacked: true)
                    }
                }
            }
        }
    }

    private func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }
}

/// A short ping run to the router: 10 pings, then latency, jitter and loss.
@MainActor
@Observable
final class RouterMeasurement {
    private(set) var isRunning = false
    private(set) var result: String?
    private(set) var error: ToolError?
    private var task: Task<Void, Never>?

    func start(gateway: String) {
        guard !isRunning else { return }
        isRunning = true
        result = nil
        error = nil
        task?.cancel()
        task = Task { [weak self] in
            var statistics = PingStatistics()
            var failure: ToolError?
            if DemoLaunch.isDemo {
                for value in [3.0, 2.0, 4.0, 3.0, 2.0, 3.0, 3.0, 4.0, 2.0, 3.0] { statistics.recordReply(milliseconds: value) }
            } else if let address = ResolvedAddress(literal: gateway) {
                var settings = PingSettings()
                settings.intervalSeconds = 0.2
                settings.timeoutSeconds = 1
                for await event in PingTool.run(address: address, settings: settings) {
                    switch event {
                    case .reply(_, _, let milliseconds, _): statistics.recordReply(milliseconds: milliseconds)
                    case .noReply: statistics.recordLoss()
                    case .failed(_, let error):
                        statistics.recordLoss()
                        failure = error
                    case .started: break
                    }
                    if statistics.sent >= 10 { break }
                }
            }
            guard let self, !Task.isCancelled else { return }
            if statistics.received == 0, let failure {
                error = failure
            } else {
                let latency = statistics.average.map { "\(Int($0.rounded())) ms" } ?? "–"
                let jitter = statistics.jitter.map { "\(Int($0.rounded())) ms" } ?? "–"
                result = "\(latency) · \(jitter) · \(Int(statistics.lostPercent.rounded())) %"
            }
            isRunning = false
        }
    }
}
