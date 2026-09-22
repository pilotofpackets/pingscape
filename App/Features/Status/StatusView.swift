import NetKit
import SwiftUI

struct StatusView: View {
    @Environment(SnapshotStore.self) private var store
    @Environment(PrivacyMask.self) private var mask
    @Environment(ExternalStore.self) private var external
    @Environment(AppNavigation.self) private var navigation
    @State private var path = DemoLaunch.overviewPath
    @State private var sections: [SectionRecord] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 24) {
                    if let snapshot = store.snapshot {
                        HeroStatus(
                            title: snapshot.isOnline ? "Online" : "Offline",
                            subtitle: heroSubtitle(snapshot),
                            tone: snapshot.isOnline ? .good : .critical,
                            systemImage: heroSymbol(snapshot),
                            chips: heroChips(snapshot))
                        // While a full tunnel carries the traffic, the VPN
                        // card is what actually governs the connection, so it
                        // leads and is marked.
                        if snapshot.tunnelScope == .full {
                            vpn(snapshot)
                            connection(snapshot)
                        } else {
                            connection(snapshot)
                            vpn(snapshot)
                        }
                        wifi(snapshot)
                        cellular(snapshot)
                        technicalDetails(snapshot)
                        Text("As of \(snapshot.takenAt.formatted(date: .omitted, time: .standard))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .readableContentWidth()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                external.load(force: true)
                await store.refresh()
            }
            .onPreferenceChange(SectionRecordsKey.self) { sections = $0 }
            .onChange(of: navigation.overviewRequest, initial: true) { _, request in
                guard let request else { return }
                path = [request]
                navigation.overviewRequest = nil
            }
            .navigationTitle("Overview")
            .navigationDestination(for: OverviewDestination.self) { destination in
                switch destination {
                case .wifi: WiFiDetailView()
                case .vpn: VPNDetailView()
                case .cellular: CellularDetailView()
                case .routing: RoutingView()
                case .dns: DNSProxyView()
                case .interfaces: InterfacesView()
                case .external: ExternalView()
                case .allRoutes: AllRoutesView()
                case .interface(let name): InterfaceDetailView(name: name)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ExportMenu(fileBaseName: "overview", header: reportHeader, sections: sections)
                        .disabled(sections.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        mask.isMasked.toggle()
                    } label: {
                        Image(systemName: mask.isMasked ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel("Hide values")
                    .accessibilityAddTraits(mask.isMasked ? .isSelected : [])
                }
            }
        }
    }

    /// Header lines of the report: exactly the rows on screen, and the hidden
    /// values stay hidden. External values are in it only if they are loaded.
    private var reportHeader: [String] {
        DeviceInfo.reportHeader(at: store.snapshot?.takenAt ?? Date())
    }

    // MARK: Hero

    private func heroSubtitle(_ snapshot: NetworkSnapshot) -> String? {
        var parts: [String] = []
        // The system's own reason, if it gives one. Otherwise nothing is said.
        if !snapshot.isOnline, let reason = snapshot.path?.unsatisfiedReason?.text {
            parts.append(reason)
        }
        if case .value(let wifi) = snapshot.wifi {
            let name = mask.shown(wifi.ssid)
            parts.append(String(localized: "via Wi-Fi “\(name)”"))
        } else if snapshot.primaryInterface?.kind == .wifi {
            parts.append(String(localized: "via Wi-Fi"))
        } else if snapshot.primaryInterface?.kind == .cellular {
            let technology = snapshot.cellularServices.first { $0.isDataService }?.technology.label
            parts.append(
                technology.map { String(localized: "via Cellular (\($0))") }
                    ?? String(localized: "via Cellular"))
        } else if snapshot.primaryInterface?.kind == .ethernet {
            parts.append(String(localized: "via Ethernet"))
        }
        if snapshot.isVPNActive { parts.append(String(localized: "VPN active")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func heroSymbol(_ snapshot: NetworkSnapshot) -> String {
        switch snapshot.primaryInterface?.kind {
        case .wifi: "wifi"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .ethernet: "cable.connector"
        default: "network"
        }
    }

    private func heroChips(_ snapshot: NetworkSnapshot) -> [String] {
        guard let path = snapshot.path, path.isOnline else { return [] }
        var chips: [String] = []
        if path.supportsIPv4 { chips.append("IPv4") }
        if path.supportsIPv6 { chips.append("IPv6") }
        if path.supportsDNS { chips.append("DNS") }
        return chips
    }

    // MARK: Cards

    @ViewBuilder
    private func connection(_ snapshot: NetworkSnapshot) -> some View {
        // A full tunnel decides the system's DNS servers and what an outside
        // server sees, so those two rows move to the VPN card below (or
        // above), which is what determines them. The address, gateway and
        // proxy stay here: they belong to this connection regardless of a VPN.
        let fullTunnel = snapshot.tunnelScope == .full
        InfoSection(title: "Connection") {
            if let ipv4 = snapshot.primaryIPv4 {
                Rows.address(ipv4)
            }
            if let gateway = snapshot.localGateway4 {
                DataRow(label: "Default gateway", value: gateway, monospaced: true, sensitive: true)
            }
            if let ipv6 = snapshot.primaryIPv6 {
                Rows.address(ipv6)
            }
            if !fullTunnel {
                if !snapshot.dnsServers.isEmpty {
                    DataRow(
                        label: "DNS servers", value: snapshot.dnsServers.joined(separator: "\n"),
                        monospaced: true, sensitive: true)
                }
                LoadableRow(label: "External IPv4", state: external.ipv4) { external.load(userRequested: true) }
                LoadableRow(label: "External IPv6", state: external.ipv6, stacked: true) {
                    external.load(userRequested: true)
                }
            } else if let name = snapshot.primaryInterface?.name {
                // The VPN carries the default route, so a plain request would
                // only repeat the VPN card's external IP. This one is bound to
                // the interface underneath, around the tunnel.
                LoadableRow(label: "External IPv4", state: external.boundIPv4) {
                    external.loadBound(interfaceName: name, userRequested: true)
                }
                LoadableRow(label: "External IPv6", state: external.boundIPv6, stacked: true) {
                    external.loadBound(interfaceName: name, userRequested: true)
                }
            }
            DataRow(
                label: "Proxy", value: proxyDescription(snapshot.proxy),
                monospaced: snapshot.proxy.isEnabled, sensitive: snapshot.proxy.isEnabled)
        }
    }

    private func proxyDescription(_ proxy: ProxyInfo) -> String {
        guard proxy.isEnabled else { return String(localized: "Off") }
        if let pac = proxy.pacURL { return pac }
        guard let host = proxy.host else { return String(localized: "On") }
        return proxy.port.map { "\(host):\($0)" } ?? host
    }

    @ViewBuilder
    private func wifi(_ snapshot: NetworkSnapshot) -> some View {
        switch snapshot.wifi {
        case .value(let info):
            InfoSection(title: "Wi-Fi", details: OverviewDestination.wifi) {
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
            }
        case .needsPermission:
            InfoSection(title: "Wi-Fi") {
                WiFiPermissionPrompt()
            }
        case .loading, .failed, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func vpn(_ snapshot: NetworkSnapshot) -> some View {
        if let scope = snapshot.tunnelScope {
            InfoSection(title: "VPN and Tunnel", details: OverviewDestination.vpn, prominent: scope == .full) {
                // "Status" is inside the loop, not a row of its own before it:
                // a plain row directly followed by a ForEach, both direct
                // children of one card, made the card's divider mechanism
                // (`Group(subviews:)`) drop the divider around some of the
                // ForEach's own rows (found 2026-09-22; harmless to repeat
                // per tunnel, there is normally exactly one).
                ForEach(snapshot.vpnInterfaces) { tunnel in
                    StatusRow(
                        label: "Status",
                        text: scope == .full
                            ? String(localized: "Active · Full tunnel")
                            : String(localized: "Active · Split tunnel"))
                    DataRow(label: "Interface", value: tunnel.name, monospaced: true)
                    Rows.addresses(of: tunnel)
                }
                // Only while this carries the default route: everything the
                // internet resolves and sees is really the tunnel's, not the
                // Wi-Fi or cellular connection underneath (see the Connection card).
                if scope == .full {
                    if !snapshot.dnsServers.isEmpty {
                        DataRow(
                            label: "DNS servers", value: snapshot.dnsServers.joined(separator: "\n"),
                            monospaced: true, sensitive: true)
                    }
                    LoadableRow(label: "External IPv4", state: external.ipv4) { external.load(userRequested: true) }
                    LoadableRow(label: "External IPv6", state: external.ipv6, stacked: true) {
                        external.load(userRequested: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellular(_ snapshot: NetworkSnapshot) -> some View {
        let services = snapshot.knownCellularServices
        if !services.isEmpty {
            InfoSection(title: "Cellular", details: OverviewDestination.cellular) {
                ForEach(services) { service in
                    StatusRow(
                        label: service.title(among: snapshot.cellularServices.count),
                        text: service.technology.label)
                }
            }
        }
    }

    /// The pages for people who want to see how the connection is built.
    private func technicalDetails(_ snapshot: NetworkSnapshot) -> some View {
        InfoSection(title: "Technical details") {
            if !snapshot.defaultRoutes.isEmpty || snapshot.path != nil {
                LinkRow(label: "Routing", value: OverviewDestination.routing)
            }
            LinkRow(label: "DNS and Proxy", value: OverviewDestination.dns)
            LinkRow(label: "External", value: OverviewDestination.external)
            LinkRow(
                label: "Interfaces", detail: String(snapshot.interfaces.count),
                value: OverviewDestination.interfaces)
        }
    }
}
