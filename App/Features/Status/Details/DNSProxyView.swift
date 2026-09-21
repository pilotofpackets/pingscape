import NetKit
import SwiftUI

struct DNSProxyView: View {
    @Environment(SnapshotStore.self) private var store
    @State private var timings: [String: DNSTiming] = [:]
    @State private var isMeasuring = false
    @State private var nat64Prefix: String?

    var body: some View {
        DetailPage(title: "DNS and Proxy") {
            if let snapshot = store.snapshot {
                if !snapshot.dnsServers.isEmpty {
                    InfoSection(title: "DNS servers") {
                        ForEach(snapshot.dnsServers, id: \.self) { server in
                            DataRow(label: "DNS server", value: server, monospaced: true, sensitive: true)
                            if let timing = timings[server] {
                                DataRow(label: "Response time", value: timing.text)
                            }
                        }
                        if isMeasuring {
                            LoadingRow(label: "Measuring")
                        } else {
                            PermissionRow(label: "Response time", buttonTitle: "Measure response time") {
                                measure(snapshot.dnsServers)
                            }
                        }
                    }
                }
                if let nat64Prefix {
                    InfoSection(title: "NAT64") {
                        DataRow(label: "Prefix", value: nat64Prefix, monospaced: true, sensitive: true)
                    }
                }
                InfoSection(title: "Proxy") {
                    proxyRows(snapshot.proxy)
                }
            }
        }
        .task {
            nat64Prefix = DemoLaunch.isDemo ? nil : await Task.detached { NAT64Collector.prefix() }.value
        }
    }

    private func measure(_ servers: [String]) {
        isMeasuring = true
        timings = [:]
        Task {
            await withTaskGroup(of: (String, DNSTiming).self) { group in
                for server in servers {
                    group.addTask {
                        if DemoLaunch.isDemo { return (server, .milliseconds(8)) }
                        guard let address = ResolvedAddress(literal: server) else { return (server, .noAnswer) }
                        do { return (server, .milliseconds(try await DNSClient.measure(server: address))) } catch { return (server, .noAnswer) }
                    }
                }
                for await (server, timing) in group { timings[server] = timing }
            }
            isMeasuring = false
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

/// The answer time of one DNS server, or that it did not answer.
enum DNSTiming {
    case milliseconds(Double)
    case noAnswer

    var text: String {
        switch self {
        case .milliseconds(let value): "\(Int(value.rounded())) ms"
        case .noAnswer: String(localized: "No answer")
        }
    }
}
