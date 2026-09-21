import NetKit
import SwiftUI

/// The expert view: every interface the system lists, including `awdl0` and
/// `llw0`, without a claim about what they do.
struct InterfacesView: View {
    @Environment(SnapshotStore.self) private var store

    var body: some View {
        DetailPage(title: "Interfaces") {
            if let snapshot = store.snapshot {
                InfoSection(title: "All interfaces") {
                    ForEach(Self.sorted(snapshot.interfaces)) { interface in
                        NavigationLink(value: OverviewDestination.interface(interface.name)) {
                            InterfaceRow(interface: interface)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// By name, with numbers in order: `utun2` before `utun10`.
    static func sorted(_ interfaces: [NetworkInterface]) -> [NetworkInterface] {
        interfaces.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct InterfaceRow: View {
    let interface: NetworkInterface

    private var name: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: interface.name)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
            if let label = interface.kind.label {
                Text(label).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            StatusDot(tone: interface.isRunning ? .good : .neutral)
            Text(interface.isRunning ? "Running" : "Not running")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }

    var body: some View {
        HStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    name
                    Spacer(minLength: 8)
                    status
                }
                VStack(alignment: .leading, spacing: 4) {
                    name
                    status
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct InterfaceDetailView: View {
    @Environment(SnapshotStore.self) private var store
    let name: String

    var body: some View {
        let interface = store.snapshot?.interfaces.first { $0.name == name }
        DetailPage(title: LocalizedStringResource(stringLiteral: name), isAvailable: interface != nil || store.snapshot == nil) {
            if let interface {
                InfoSection(title: "Interface") {
                    StatusRow(
                        label: "Status",
                        text: interface.isRunning ? String(localized: "Running") : String(localized: "Not running"),
                        tone: interface.isRunning ? .good : .neutral)
                    let flags = interface.flags.names
                    if !flags.isEmpty {
                        DataRow(
                            label: "Flags", value: flags.joined(separator: ", "), monospaced: true,
                            stacked: true)
                    }
                    if let mtu = interface.mtu {
                        DataRow(label: "MTU", value: String(mtu))
                    }
                }
                // Every address the interface holds, link-local ones too.
                if !interface.addresses.isEmpty {
                    InfoSection(title: "Addresses") {
                        ForEach(interface.addresses, id: \.self) { Rows.address($0) }
                    }
                }
                counters(interface)
            }
        }
    }

    @ViewBuilder
    private func counters(_ interface: NetworkInterface) -> some View {
        if let received = interface.receivedBytes, let sent = interface.sentBytes {
            InfoSection(title: "Data since restart") {
                DataRow(label: "Received", value: ByteCount.string(received))
                DataRow(label: "Sent", value: ByteCount.string(sent))
                if let packets = interface.receivedPackets {
                    DataRow(label: "Packets received", value: ByteCount.number(packets))
                }
                if let packets = interface.sentPackets {
                    DataRow(label: "Packets sent", value: ByteCount.number(packets))
                }
            }
        }
    }
}
