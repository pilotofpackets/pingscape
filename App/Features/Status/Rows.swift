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
