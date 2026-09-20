import NetKit
import SwiftUI

struct StatusView: View {
    @Environment(SnapshotStore.self) private var store
    @Environment(PrivacyMask.self) private var mask

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let snapshot = store.snapshot {
                        HeroStatus(
                            title: snapshot.isOnline ? "Online" : "Offline",
                            subtitle: heroSubtitle(snapshot),
                            tone: snapshot.isOnline ? .good : .critical,
                            systemImage: heroSymbol(snapshot),
                            chips: heroChips(snapshot))
                        connection(snapshot)
                        wifi(snapshot)
                        vpn(snapshot)
                        cellular(snapshot)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await store.refresh() }
            .navigationTitle("Overview")
            .toolbar {
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

    // MARK: Hero

    private func heroSubtitle(_ snapshot: NetworkSnapshot) -> String? {
        var parts: [String] = []
        if case .value(let wifi) = snapshot.wifi {
            let name = mask.isMasked ? "•••••••" : wifi.ssid
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
        InfoSection(title: "Connection") {
            if let ipv4 = snapshot.primaryIPv4 {
                addressRows(ipv4)
            }
            if let gateway = snapshot.localGateway4 {
                DataRow(label: "Default gateway", value: gateway, monospaced: true, sensitive: true)
            }
            if let ipv6 = snapshot.primaryIPv6 {
                addressRows(ipv6)
            }
            if !snapshot.dnsServers.isEmpty {
                DataRow(
                    label: "DNS servers", value: snapshot.dnsServers.joined(separator: "\n"),
                    monospaced: true, sensitive: true)
            }
            DataRow(label: "Proxy", value: proxyDescription(snapshot.proxy))
        }
    }

    /// An IPv4 address and its subnet mask as two rows, so each fits on one
    /// line. An IPv6 address keeps its prefix and may wrap.
    @ViewBuilder
    private func addressRows(_ address: InterfaceAddress) -> some View {
        if address.isIPv6 {
            DataRow(
                label: "IPv6 address", value: address.withPrefix, monospaced: true, sensitive: true,
                stacked: true)
        } else {
            DataRow(label: "IP address", value: address.ip, monospaced: true, sensitive: true)
            if let mask = address.netmask ?? address.prefixLength.map(IPv4.netmask(fromPrefix:)) {
                DataRow(label: "Subnet mask", value: mask, monospaced: true)
            }
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
            InfoSection(title: "Wi-Fi") {
                DataRow(label: "Name (SSID)", value: info.ssid, sensitive: true)
                if let bssid = info.bssid {
                    DataRow(label: "BSSID", value: bssid, monospaced: true, sensitive: true)
                    if let vendor = store.oui.vendor(forBSSID: bssid) {
                        DataRow(label: "Vendor", value: vendor)
                    }
                }
                if let security = securityLabel(info.security) {
                    DataRow(label: "Security", value: security)
                }
            }
        case .needsPermission:
            InfoSection(title: "Wi-Fi") {
                PermissionRow(label: "Wi-Fi name", buttonTitle: "Allow") {
                    store.location.request()
                }
            }
        case .loading, .failed, .none:
            EmptyView()
        }
    }

    private func securityLabel(_ security: WiFiSecurity) -> String? {
        switch security {
        case .open: String(localized: "Open")
        case .wep: "WEP"
        case .personal: "WPA2/WPA3 Personal"
        case .enterprise: "WPA2/WPA3 Enterprise"
        case .unknown: nil
        }
    }

    @ViewBuilder
    private func vpn(_ snapshot: NetworkSnapshot) -> some View {
        if let scope = snapshot.tunnelScope {
            InfoSection(title: "VPN and Tunnel") {
                StatusRow(
                    label: "Status",
                    text: scope == .full
                        ? String(localized: "Active · Full tunnel")
                        : String(localized: "Active · Split tunnel"))
                ForEach(snapshot.vpnInterfaces) { tunnel in
                    DataRow(label: "Interface", value: tunnel.name, monospaced: true)
                    if let address = tunnel.usableAddresses.first(where: { !$0.isIPv6 })
                        ?? tunnel.usableAddresses.first
                    {
                        addressRows(address)
                    }
                    if let mtu = tunnel.mtu {
                        DataRow(label: "MTU", value: String(mtu))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellular(_ snapshot: NetworkSnapshot) -> some View {
        if !snapshot.cellularServices.isEmpty {
            InfoSection(title: "Cellular") {
                ForEach(snapshot.cellularServices) { service in
                    StatusRow(
                        label: cellularLabel(service, total: snapshot.cellularServices.count),
                        text: service.technology.label)
                }
            }
        }
    }

    private func cellularLabel(_ service: CellularService, total: Int) -> LocalizedStringKey {
        if service.isDataService { return "Data SIM" }
        return total > 2 ? "Other SIM" : "Second SIM"
    }
}

extension NetworkSnapshot {
    /// Online if the system says so, otherwise if any local interface has an address.
    fileprivate var isOnline: Bool {
        path?.isOnline ?? (primaryInterface != nil)
    }
}
