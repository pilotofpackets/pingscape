import NetKit
import SwiftUI
import WidgetKit

// A widget shows a state that iOS asked for at a time of its own choosing,
// not the state right now. So it always shows its own time ("As of 14:05") and
// nothing that would be wrong when old: no addresses, no names. Only whether
// the device is online, over what, and whether a VPN is active.

struct StatusEntry: WidgetKit.TimelineEntry {
    let date: Date
    let isOnline: Bool
    let connection: ConnectionKind
    let isVPNActive: Bool
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), isOnline: true, connection: .wifi, isVPNActive: false)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StatusEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await Self.entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StatusEntry>) -> Void) {
        Task {
            let entry = await Self.entry()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    private static func entry() async -> StatusEntry {
        let snapshot = await LiveSnapshotProvider().snapshot()
        return StatusEntry(
            date: Date(), isOnline: snapshot.isOnline, connection: snapshot.connectionKind, isVPNActive: snapshot.isVPNActive)
    }
}

extension ConnectionKind {
    var symbol: String {
        switch self {
        case .wifi: "wifi"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .ethernet: "cable.connector"
        case .other: "network"
        case .offline: "network.slash"
        }
    }

    /// "via Wi-Fi". `nil` when the kind adds nothing.
    var via: LocalizedStringResource? {
        switch self {
        case .wifi: "via Wi-Fi"
        case .cellular: "via Cellular"
        case .ethernet: "via Ethernet"
        case .other, .offline: nil
        }
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private var title: LocalizedStringResource { entry.isOnline ? "Online" : "Offline" }
    private var stand: Text { Text("As of \(entry.date.formatted(date: .omitted, time: .shortened))") }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label {
                Text(title)
            } icon: {
                Image(systemName: entry.connection.symbol)
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.isVPNActive ? "lock.shield" : entry.connection.symbol)
                    .font(.title2)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    Image(systemName: entry.connection.symbol)
                }
                if let via = entry.connection.via { Text(via) }
                if entry.isVPNActive { Text("VPN active") }
                stand.font(.caption2).foregroundStyle(.secondary)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(entry.isOnline ? Color.green : Color.red).frame(width: 9, height: 9).accessibilityHidden(true)
                    Text(title).font(.headline)
                }
                if let via = entry.connection.via {
                    Label {
                        Text(via)
                    } icon: {
                        Image(systemName: entry.connection.symbol)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                if entry.isVPNActive {
                    Label("VPN active", systemImage: "lock.shield").font(.subheadline)
                }
                Spacer(minLength: 0)
                stand.font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.pingscape.widget.status", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Network status")
        .description("Whether the device is online, over what, and whether a VPN is active. It shows the time it was read.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

@main
struct PingscapeWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
    }
}
