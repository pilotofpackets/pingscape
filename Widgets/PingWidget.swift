import AppIntents
import NetKit
import SwiftUI
import WidgetKit

// Three pings to a host the user picks, or to the default gateway. The
// widget measures when iOS reads it (about every 15 minutes) and on ↻.

struct PingConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Ping"
    static let description = IntentDescription("Choose the host. Without one, the widget pings the default gateway.")

    @Parameter(title: "Host", description: "A host name or IP address. Empty: the default gateway")
    var host: String?
}

struct PingEntry: WidgetKit.TimelineEntry {
    enum Outcome {
        case replies(average: Double, received: Int, sent: Int)
        /// Every ping went unanswered.
        case noReply(sent: Int)
        case failed(String)
        /// No host set and no local gateway (cellular, offline).
        case noTarget
    }

    let date: Date
    /// What was pinged, as entered, or "Gateway".
    let target: String?
    let isGateway: Bool
    let outcome: Outcome

    static let placeholder = PingEntry(
        date: Date(), target: "192.168.178.1", isGateway: true, outcome: .replies(average: 3.4, received: 3, sent: 3))
}

struct PingProvider: AppIntentTimelineProvider {
    static let count = 3

    func placeholder(in context: Context) -> PingEntry { .placeholder }

    func snapshot(for configuration: PingConfiguration, in context: Context) async -> PingEntry {
        if context.isPreview { return .placeholder }
        return await entry(for: configuration)
    }

    func timeline(for configuration: PingConfiguration, in context: Context) async -> Timeline<PingEntry> {
        Timeline(entries: [await entry(for: configuration)], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: PingConfiguration) async -> PingEntry {
        let typed = configuration.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name: String
        let isGateway = typed.isEmpty
        if isGateway {
            guard let gateway = await WidgetSnapshot.read().localGateway4 else {
                return PingEntry(date: Date(), target: nil, isGateway: true, outcome: .noTarget)
            }
            name = gateway
        } else {
            name = typed
        }
        return PingEntry(date: Date(), target: name, isGateway: isGateway, outcome: await Self.ping(name))
    }

    private static func ping(_ text: String) async -> PingEntry.Outcome {
        let address: ResolvedAddress
        do {
            guard let first = try await HostResolver.resolve(try ToolInput.host(text)).first else {
                return .failed(ToolError.cannotResolve.widgetText)
            }
            address = first
        } catch let error as ToolError {
            return .failed(error.widgetText)
        } catch {
            return .failed(String(localized: "This is not a valid host name or IP address"))
        }

        var settings = PingSettings()
        settings.intervalSeconds = 0.5
        settings.timeoutSeconds = 1.5
        var times: [Double] = []
        var sent = 0
        for await event in PingTool.run(address: address, settings: settings) {
            switch event {
            case .reply(_, _, let milliseconds, _):
                times.append(milliseconds)
                sent += 1
            case .noReply, .tooBig:
                sent += 1
            case .failed(_, let error):
                if error == .notPermitted, address.isLocal {
                    return .failed(String(localized: "Local network access is not allowed"))
                }
                return .failed(error.widgetText)
            case .started:
                continue
            }
            if sent >= count { break }
        }
        guard !times.isEmpty else { return .noReply(sent: sent) }
        return .replies(average: times.reduce(0, +) / Double(times.count), received: times.count, sent: sent)
    }
}

struct PingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PingEntry

    private var targetText: String {
        if entry.isGateway { return String(localized: "Gateway") }
        return entry.target ?? ""
    }

    private var resultText: String {
        switch entry.outcome {
        case .replies(let average, _, _): widgetMilliseconds(average)
        case .noReply: String(localized: "No answer")
        case .failed(let text): text
        case .noTarget: String(localized: "No local gateway right now")
        }
    }

    private var lossText: String? {
        switch entry.outcome {
        case .replies(_, let received, let sent) where received < sent:
            String(localized: "\(received) of \(sent) answered")
        default: nil
        }
    }

    private var isGood: Bool {
        if case .replies = entry.outcome { return true }
        return false
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label {
                Text("\(targetText): \(resultText)")
            } icon: {
                Image(systemName: "dot.radiowaves.left.and.right")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    if case .replies(let average, _, _) = entry.outcome {
                        Text("\(Int(average.rounded()))").font(.title3.weight(.semibold)).minimumScaleFactor(0.5)
                        Text("ms").font(.caption2)
                    } else {
                        Image(systemName: "exclamationmark.triangle").font(.title3)
                    }
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Ping", systemImage: "dot.radiowaves.left.and.right").font(.caption2).foregroundStyle(.secondary)
                Text(resultText).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                Text(targetText).font(.caption).lineLimit(1).privacySensitive(!entry.isGateway)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("Ping", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(targetText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .privacySensitive(!entry.isGateway)
                Text(resultText)
                    .font(isGood ? .title.weight(.semibold) : .subheadline)
                    .monospacedDigit()
                    .foregroundStyle(isGood ? .primary : .secondary)
                    .lineLimit(isGood ? 1 : 3)
                    .minimumScaleFactor(0.6)
                if let lossText { Text(lossText).font(.caption).foregroundStyle(.orange) }
                Spacer(minLength: 0)
                WidgetFooter(date: entry.date)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "app.pingscape.widget.ping", intent: PingConfiguration.self, provider: PingProvider()) {
            entry in
            PingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(AppPage.ping.url)
        }
        .configurationDisplayName("Ping")
        .description("The round trip to a host or to the default gateway, from three pings. Tap ↻ to measure again.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}
