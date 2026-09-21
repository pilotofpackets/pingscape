import NetKit
import SwiftUI

struct DNSProxyView: View {
    @Environment(SnapshotStore.self) private var store

    var body: some View {
        DetailPage(title: "DNS and Proxy") {
            if let snapshot = store.snapshot {
                if !snapshot.dnsServers.isEmpty {
                    InfoSection(title: "DNS servers") {
                        Rows.dnsServers(snapshot.dnsServers)
                    }
                }
                InfoSection(title: "Proxy") {
                    proxyRows(snapshot.proxy)
                }
            }
        }
    }

    @ViewBuilder
    private func proxyRows(_ proxy: ProxyInfo) -> some View {
        if !proxy.isEnabled {
            DataRow(label: "Proxy", value: String(localized: "Off"))
        } else if let pac = proxy.pacURL {
            DataRow(label: "Proxy auto-configuration", value: pac, monospaced: true, sensitive: true, stacked: true)
        } else if let host = proxy.host {
            DataRow(label: "HTTP proxy", value: host, monospaced: true, sensitive: true)
            if let port = proxy.port {
                DataRow(label: "Port", value: String(port), monospaced: true)
            }
        }
    }
}
