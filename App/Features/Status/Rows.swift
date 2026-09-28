import NetKit
import SwiftUI

/// Groups of rows that several pages share, prebuilt as plain arrays with
/// ordinary Swift `for`/`if` rather than `ForEach`/SwiftUI-`if`, and meant to
/// be rendered through `RowList`. `InfoCard`'s divider mechanism
/// (`Group(subviews:)`) has repeatedly dropped the divider at the seam where
/// a plain row sits directly next to a `ForEach` or SwiftUI-`if` — even
/// nested one level deep inside another `ForEach`'s own per-item content —
/// including seams entirely inside what used to be `addresses(of:)` itself
/// (found 2026-09-22 and 2026-09-28, real-device only). Returning `[AnyView]`
/// and combining arrays with `append(contentsOf:)` removes every such seam
/// before the content ever reaches `Group(subviews:)`.
@MainActor
enum Rows {
    /// An IPv4 address and its subnet mask as two rows, so each fits on one
    /// line. An IPv6 address keeps its prefix and may wrap.
    static func address(_ address: InterfaceAddress) -> [AnyView] {
        if address.isIPv6 {
            return [
                AnyView(
                    DataRow(
                        label: "IPv6 address", value: address.withPrefix, monospaced: true, sensitive: true,
                        stacked: true))
            ]
        }
        var rows: [AnyView] = [
            AnyView(DataRow(label: "IP address", value: address.ip, monospaced: true, sensitive: true))
        ]
        if let mask = address.netmask ?? address.prefixLength.map(IPv4.netmask(fromPrefix:)) {
            rows.append(AnyView(DataRow(label: "Subnet mask", value: mask, monospaced: true, sensitive: true)))
        }
        return rows
    }

    /// The usable IPv4 addresses of an interface, its default gateway, the
    /// usable IPv6 addresses, then the MTU.
    static func addresses(of interface: NetworkInterface, gateway: String? = nil) -> [AnyView] {
        var rows = interface.ipv4Addresses.flatMap { address($0) }
        if let gateway {
            rows.append(AnyView(DataRow(label: "Default gateway", value: gateway, monospaced: true, sensitive: true)))
        }
        rows.append(contentsOf: interface.ipv6Addresses.flatMap { address($0) })
        if let mtu = interface.mtu {
            rows.append(AnyView(DataRow(label: "MTU", value: String(mtu))))
        }
        return rows
    }

    /// The system DNS servers, one row each.
    static func dnsServers(_ servers: [String]) -> [AnyView] {
        servers.map { AnyView(DataRow(label: "DNS server", value: $0, monospaced: true, sensitive: true)) }
    }
}

/// Renders rows built as a plain array through one array-backed `ForEach`, so
/// nothing here is a sibling `ForEach`/conditional for `InfoCard`'s divider
/// mechanism to trip over. See `Rows`.
struct RowList: View {
    let rows: [AnyView]

    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            row
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
/// (no IPv6) leaves the row out, unless `unavailableText` names what to show
/// instead (for a row with a sibling that does show, like "External IPv4"
/// next to "External IPv6", where a missing row reads as unbalanced).
struct LoadableRow: View {
    let label: LocalizedStringResource
    let state: LoadState<String>
    var monospaced = true
    var sensitive = true
    var stacked = false
    /// A short explanation shown under the value once it is loaded.
    var note: LocalizedStringResource?
    var unavailableText: LocalizedStringResource?
    let load: () -> Void

    var body: some View {
        switch state {
        case .loaded(let value):
            DataRow(
                label: label, value: value, monospaced: monospaced, sensitive: sensitive, stacked: stacked, note: note)
        case .loading:
            LoadingRow(label: label)
        case .notLoaded:
            PermissionRow(label: label, buttonTitle: "Load", action: load)
        case .failed(let reason):
            PermissionRow(label: label, buttonTitle: "Try again", detail: reason, action: load)
        case .unavailable:
            if let unavailableText {
                DataRow(label: label, value: String(localized: unavailableText))
            } else {
                EmptyView()
            }
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
