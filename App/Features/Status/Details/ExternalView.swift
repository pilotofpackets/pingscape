import NetKit
import SwiftUI

/// The public address and the provider behind it. Everything here is loaded on
/// request from the services listed under "Source".
struct ExternalView: View {
    @Environment(ExternalStore.self) private var external
    @State private var showsSource = false

    var body: some View {
        DetailPage(title: "External") {
            if !external.isEnabled, external.ipv4.value == nil, !external.ipv4.isLoading {
                InfoSection(title: "Public IP address") {
                    LoadableRow(label: "IPv4 address", state: external.ipv4) { external.load(userRequested: true) }
                }
            } else {
                publicAddress
                providerSection
            }
            reachability
            Text("Network data: RIPEstat, RIPE NCC")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsSource = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Source")
            }
        }
        .sheet(isPresented: $showsSource) { ExternalSourceSheet() }
        .task { external.load() }
    }

    private var publicAddress: some View {
        InfoSection(title: "Public IP address") {
            LoadableRow(label: "IPv4 address", state: external.ipv4) { external.load(userRequested: true) }
            LoadableRow(label: "IPv6 address", state: external.ipv6, stacked: true) {
                external.load(userRequested: true)
            }
            LoadableRow(label: "Reverse DNS", state: external.reverseName, monospaced: false, stacked: true) {
                external.load(userRequested: true)
            }
        }
    }

    @ViewBuilder
    private var providerSection: some View {
        switch external.provider {
        case .unavailable:
            EmptyView()
        case .loaded(let info):
            InfoSection(title: "Provider (AS)") {
                DataRow(label: "AS number", value: info.asNumber, monospaced: true)
                if let organization = info.organization {
                    DataRow(label: "Organization", value: organization)
                }
                if let network = info.network {
                    DataRow(label: "Network", value: network, monospaced: true, sensitive: true)
                }
            }
        default:
            InfoSection(title: "Provider (AS)") {
                LoadableRow(label: "AS number", state: external.provider.map { $0.asNumber }) {
                    external.load(userRequested: true)
                }
            }
        }
    }

    private var reachability: some View {
        InfoSection(title: "Reachability") {
            switch external.internetCheck {
            case .loaded(let result):
                StatusRow(label: "Internet", text: result.text, tone: result.tone)
                PermissionRow(label: "Internet", buttonTitle: "Check again") { external.checkInternet() }
            case .loading:
                LoadingRow(label: "Internet")
            default:
                PermissionRow(label: "Internet", buttonTitle: "Check internet") { external.checkInternet() }
            }
        }
    }
}

extension InternetCheck {
    var text: String {
        switch self {
        case .reachable: String(localized: "Reachable")
        case .captivePortal: String(localized: "A sign-in page answers")
        case .unreachable: String(localized: "Not reachable")
        }
    }

    var tone: StatusDot.Tone {
        switch self {
        case .reachable: .good
        case .captivePortal: .warning
        case .unreachable: .critical
        }
    }
}

extension LoadState {
    func map<T: Sendable>(_ transform: (Value) -> T) -> LoadState<T> {
        switch self {
        case .notLoaded: .notLoaded
        case .loading: .loading
        case .loaded(let value): .loaded(transform(value))
        case .failed: .failed
        case .unavailable: .unavailable
        }
    }
}

/// Which servers are asked, what is sent and why.
private struct ExternalSourceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    source("api.ipify.org", detail: "Your public IPv4 address")
                    source("api6.ipify.org", detail: "Your public IPv6 address")
                    source("stat.ripe.net", detail: "Provider and organization of the public address (RIPEstat, RIPE NCC)")
                    source("System DNS server", detail: "The name that belongs to the public address")
                } header: {
                    Text("Asked when you load")
                } footer: {
                    Text("Each server sees your public IP address, as with any request. Nothing else is sent: no device data, no location. There is no server of Pingscape.")
                }
                Section {
                    source("captive.apple.com", detail: "Only when you tap “Check internet”")
                } header: {
                    Text("Asked on a tap")
                }
            }
            .navigationTitle("Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func source(_ host: String, detail: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: host).font(.system(.body, design: .monospaced))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
