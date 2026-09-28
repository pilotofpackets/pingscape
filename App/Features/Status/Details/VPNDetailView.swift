import NetKit
import SwiftUI

struct VPNDetailView: View {
    @Environment(SnapshotStore.self) private var store

    var body: some View {
        let snapshot = store.snapshot
        DetailPage(title: "VPN and Tunnel", isAvailable: snapshot?.isVPNActive ?? true) {
            if let snapshot, let scope = snapshot.tunnelScope {
                InfoSection(title: "Status") {
                    StatusRow(label: "Status", text: String(localized: "Active"))
                    DataRow(
                        label: "Scope",
                        value: scope == .full
                            ? String(localized: "Full tunnel") : String(localized: "Split tunnel"))
                }
                let tunnels = snapshot.vpnInterfaces
                ForEach(tunnels) { tunnel in
                    let title: LocalizedStringResource =
                        tunnels.count > 1 ? "Tunnel · \(tunnel.name)" : "Tunnel"
                    InfoSection(title: title) {
                        RowList(rows: tunnelRows(tunnel, snapshot: snapshot))
                    }
                    TrafficSection(interface: tunnel)
                }
            }
        }
    }

    /// Every row of one tunnel's card, flattened ahead of time. See `Rows`
    /// for why this avoids a plain row sitting next to a ForEach/conditional.
    private func tunnelRows(_ tunnel: NetworkInterface, snapshot: NetworkSnapshot) -> [AnyView] {
        var rows: [AnyView] = [AnyView(DataRow(label: "Interface", value: tunnel.name, monospaced: true))]
        rows.append(contentsOf: Rows.addresses(of: tunnel))
        // The system DNS servers are the tunnel's only while the tunnel
        // carries the internet traffic.
        if snapshot.carriesTraffic(tunnel) {
            rows.append(contentsOf: Rows.dnsServers(snapshot.dnsServers))
        }
        return rows
    }
}
