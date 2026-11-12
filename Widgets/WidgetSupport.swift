import AppIntents
import CoreLocation
import NetKit
import SwiftUI
import WidgetKit

enum WidgetSnapshot {
    /// The network state as the widget extension sees it. The Wi-Fi name needs
    /// the app's location permission, which a widget may use once the app has it
    /// (`NSWidgetWantsLocation`).
    static func read() async -> NetworkSnapshot {
        await LiveSnapshotProvider(locationAuthorized: { CLLocationManager().isAuthorizedForWidgetUpdates }).snapshot()
    }
}

/// The ↻ button in a widget. WidgetKit reads the widget again once the action
/// is done, so the action itself has nothing to do.
struct RefreshWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult { .result() }
}

/// "As of 14:05" with the ↻ button next to it. A widget shows a state from
/// the time iOS read it, so the time is always there.
struct WidgetFooter: View {
    let date: Date
    var showsButton = true

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text("As of \(date.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if showsButton {
                Button(intent: RefreshWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel(Text("Refresh"))
            }
        }
    }
}

/// The widget's own wording for a failed measurement. The app's texts are in
/// the app target; these are the same strings.
extension ToolError {
    var widgetText: String {
        switch self {
        case .cannotResolve: String(localized: "Name could not be resolved")
        case .timeout: String(localized: "No answer within the time limit")
        case .refused: String(localized: "Connection refused")
        case .noRoute: String(localized: "No network route to the target")
        case .notPermitted: String(localized: "The system did not allow the request")
        case .noRegistry, .unreadable, .handshakeFailed, .insecureConnection:
            String(localized: "The answer could not be read")
        case .failed(let message): message
        }
    }
}

/// "13 ms" or "0.4 ms", as in the app.
func widgetMilliseconds(_ value: Double) -> String {
    if value >= 10 { return "\(Int(value.rounded())) ms" }
    return "\(value.formatted(.number.precision(.fractionLength(1)))) ms"
}
