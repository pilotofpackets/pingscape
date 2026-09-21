import NetKit
import SwiftUI

struct WiFiDetailView: View {
    @Environment(SnapshotStore.self) private var store

    var body: some View {
        let snapshot = store.snapshot
        DetailPage(title: "Wi-Fi", isAvailable: snapshot.map(isAvailable) ?? true) {
            if let snapshot {
                network(snapshot)
                addresses(snapshot)
                if let interface = snapshot.interface(of: .wifi) {
                    TrafficSection(interface: interface)
                }
            }
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

    private func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }
}
