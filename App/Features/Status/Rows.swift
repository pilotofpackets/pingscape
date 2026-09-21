import NetKit
import SwiftUI

/// Groups of rows that several pages share. They are functions, not views, so
/// that the rows land in the card as separate rows with a divider between them.
@MainActor
enum Rows {
    /// An IPv4 address and its subnet mask as two rows, so each fits on one
    /// line. An IPv6 address keeps its prefix and may wrap.
    @ViewBuilder
    static func address(_ address: InterfaceAddress) -> some View {
        if address.isIPv6 {
            DataRow(
                label: "IPv6 address", value: address.withPrefix, monospaced: true, sensitive: true,
                stacked: true)
        } else {
            DataRow(label: "IP address", value: address.ip, monospaced: true, sensitive: true)
            if let mask = address.netmask ?? address.prefixLength.map(IPv4.netmask(fromPrefix:)) {
                DataRow(label: "Subnet mask", value: mask, monospaced: true, sensitive: true)
            }
        }
    }

    /// The usable IPv4 addresses of an interface, its default gateway, the
    /// usable IPv6 addresses, then the MTU.
    @ViewBuilder
    static func addresses(of interface: NetworkInterface, gateway: String? = nil) -> some View {
        ForEach(interface.ipv4Addresses, id: \.self) { address($0) }
        if let gateway {
            DataRow(label: "Default gateway", value: gateway, monospaced: true, sensitive: true)
        }
        ForEach(interface.ipv6Addresses, id: \.self) { address($0) }
        if let mtu = interface.mtu {
            DataRow(label: "MTU", value: String(mtu))
        }
    }

    /// The system DNS servers, one row each.
    @ViewBuilder
    static func dnsServers(_ servers: [String]) -> some View {
        ForEach(servers, id: \.self) { server in
            DataRow(label: "DNS server", value: server, monospaced: true, sensitive: true)
        }
    }
}

/// The byte counters of an interface since the device started. Left out
/// entirely if the system did not deliver 64-bit counters.
struct TrafficSection: View {
    let interface: NetworkInterface

    var body: some View {
        if let received = interface.receivedBytes, let sent = interface.sentBytes {
            InfoSection(title: "Data since restart") {
                DataRow(label: "Received", value: ByteCount.string(received))
                DataRow(label: "Sent", value: ByteCount.string(sent))
            }
        }
    }
}

/// A value that is loaded on request: "Load" before, a spinner while loading,
/// the value after, "Try again" after a failure. A value that does not exist
/// (no IPv6) leaves the row out.
struct LoadableRow: View {
    let label: LocalizedStringResource
    let state: LoadState<String>
    var monospaced = true
    var sensitive = true
    var stacked = false
    let load: () -> Void

    var body: some View {
        switch state {
        case .loaded(let value):
            DataRow(label: label, value: value, monospaced: monospaced, sensitive: sensitive, stacked: stacked)
        case .loading:
            LoadingRow(label: label)
        case .notLoaded:
            PermissionRow(label: label, buttonTitle: "Load", action: load)
        case .failed:
            PermissionRow(label: label, buttonTitle: "Try again", action: load)
        case .unavailable:
            EmptyView()
        }
    }
}

/// A row while its value loads. It keeps its height, so nothing jumps.
struct LoadingRow: View {
    let label: LocalizedStringResource

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
            Spacer(minLength: 8)
            ProgressView()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("Loading"))
    }
}
