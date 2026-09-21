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
                        DataRow(label: "Interface", value: tunnel.name, monospaced: true)
                        Rows.addresses(of: tunnel)
                        // The system DNS servers are the tunnel's only while
                        // the tunnel carries the internet traffic.
                        if snapshot.carriesTraffic(tunnel) {
                            Rows.dnsServers(snapshot.dnsServers)
                        }
                    }
                    TrafficSection(interface: tunnel)
                }
            }
        }
    }
}
