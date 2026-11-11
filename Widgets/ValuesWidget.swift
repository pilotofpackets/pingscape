import AppIntents
import NetKit
import SwiftUI
import WidgetKit

// The values the user picks: IP address, Wi-Fi name, gateway, DNS, VPN …
// Unlike the status widget it shows addresses and names, so it always shows
// the time it read them, has a ↻ button to read them again, and hides the
// sensitive ones while the device is locked (`privacySensitive`).

struct ValuesConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Network values"
    static let description = IntentDescription("Choose the values the widget shows.")

    @Parameter(title: "First value", default: .connection)
    var first: NetworkValue

    @Parameter(title: "Second value", default: .localIPv4)
    var second: NetworkValue

    @Parameter(title: "Third value", default: .wifiName)
    var third: NetworkValue?

    @Parameter(title: "Fourth value", default: .gateway)
    var fourth: NetworkValue?

    var values: [NetworkValue] { [first, second, third, fourth].compactMap { $0 } }
}

struct ValuesEntry: WidgetKit.TimelineEntry {
    struct Row: Identifiable {
        let value: NetworkValue
        /// The value, or a hint when the permission is missing.
        let text: String
        let needsPermission: Bool
        var id: NetworkValue { value }
    }

    let date: Date
    let rows: [Row]

    /// A value the device does not have right now gets no row.
    init(date: Date, values: [NetworkValue], snapshot: NetworkSnapshot) {
        self.date = date
        var seen = Set<NetworkValue>()
        rows = values.filter { seen.insert($0).inserted }.compactMap { value in
            switch value.read(from: snapshot) {
            case .success(let items): Row(value: value, text: items.joined(separator: ", "), needsPermission: false)
            case .failure(.needsLocation):
                Row(value: value, text: String(localized: "Allow location in Pingscape"), needsPermission: true)
            case .failure(.notPresent): nil
            }
        }
    }

    static let placeholder = ValuesEntry(
        date: Date(), values: [.connection, .localIPv4, .wifiName, .gateway], snapshot: DemoData.snapshot)
}

struct ValuesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ValuesEntry { .placeholder }

    func snapshot(for configuration: ValuesConfiguration, in context: Context) async -> ValuesEntry {
        if context.isPreview {
            return ValuesEntry(date: Date(), values: configuration.values, snapshot: DemoData.snapshot)
        }
        return await entry(for: configuration)
    }

    func timeline(for configuration: ValuesConfiguration, in context: Context) async -> Timeline<ValuesEntry> {
        Timeline(entries: [await entry(for: configuration)], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: ValuesConfiguration) async -> ValuesEntry {
        ValuesEntry(date: Date(), values: configuration.values, snapshot: await WidgetSnapshot.read())
    }
}

struct ValuesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ValuesEntry

    /// As many rows as fit the size.
    private var rows: [ValuesEntry.Row] {
        switch family {
        case .accessoryInline: Array(entry.rows.prefix(1))
        case .systemSmall: Array(entry.rows.prefix(2))
        case .accessoryRectangular: Array(entry.rows.prefix(3))
        default: Array(entry.rows.prefix(4))
        }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let row = rows.first {
                Label {
                    Text(row.text).privacySensitive(row.value.isSensitive)
                } icon: {
                    Image(systemName: row.value.symbol)
                }
            } else {
                Text("No values right now")
            }
        case .accessoryRectangular:
            // Three short lines fit; the symbol says which value it is.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    Label {
                        Text(row.text).lineLimit(1).minimumScaleFactor(0.6).privacySensitive(row.value.isSensitive)
                    } icon: {
                        Image(systemName: row.value.symbol)
                    }
                    .accessibilityLabel(Text("\(row.value.title): \(row.text)"))
                }
                if rows.isEmpty { Text("No values right now") }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: rows.count, by: 2)), id: \.self) { index in
                        GridRow {
                            ValueCell(row: rows[index])
                            if index + 1 < rows.count {
                                ValueCell(row: rows[index + 1])
                            } else {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                        }
                    }
                }
                if rows.isEmpty { Text("No values right now").font(.headline) }
                Spacer(minLength: 0)
                WidgetFooter(date: entry.date)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { ValueCell(row: $0) }
                if rows.isEmpty { Text("No values right now").font(.headline) }
                Spacer(minLength: 0)
                WidgetFooter(date: entry.date)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ValueCell: View {
    let row: ValuesEntry.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text(row.value.title)
            } icon: {
                Image(systemName: row.value.symbol)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Text(row.text)
                .font(row.needsPermission ? .caption : .subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(row.needsPermission ? .secondary : .primary)
                .lineLimit(row.value == .dnsServers ? 2 : 1)
                .minimumScaleFactor(0.6)
                .privacySensitive(row.value.isSensitive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ValuesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "app.pingscape.widget.values", intent: ValuesConfiguration.self, provider: ValuesProvider()
        ) { entry in
            ValuesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(AppPage.overview.url)
        }
        .configurationDisplayName("Network values")
        .description("The values you choose, such as the IP address, Wi-Fi name or gateway. Tap ↻ to read them again.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
