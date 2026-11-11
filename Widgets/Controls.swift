import AppIntents
import NetKit
import SwiftUI
import WidgetKit

// Control Center, Lock Screen and Action button (iOS 18). Controls can only
// run an action, so both open a page of the app.

struct ConnectionState: Sendable {
    let isOnline: Bool
    let kind: ConnectionKind
    let isVPNActive: Bool

    var title: String {
        guard isOnline else { return String(localized: "Offline") }
        let name =
            switch kind {
            case .wifi: String(localized: "Wi-Fi")
            case .cellular: String(localized: "Cellular")
            case .ethernet: String(localized: "Ethernet")
            case .other, .offline: String(localized: "Online")
            }
        return isVPNActive ? name + " · VPN" : name
    }

    var symbol: String {
        if !isOnline { return "network.slash" }
        if isVPNActive { return "lock.shield" }
        return kind.symbol
    }
}

/// Shows how the device is connected, right when Control Center opens.
struct ConnectionControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: ConnectionState { ConnectionState(isOnline: true, kind: .wifi, isVPNActive: false) }

        func currentValue() async throws -> ConnectionState {
            let snapshot = await LiveSnapshotProvider().snapshot()
            return ConnectionState(
                isOnline: snapshot.isOnline, kind: snapshot.connectionKind, isVPNActive: snapshot.isVPNActive)
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.pingscape.control.connection", provider: Provider()) { state in
            ControlWidgetButton(action: OpenURLIntent(AppPage.overview.url)) {
                Label(state.title, systemImage: state.symbol)
            }
        }
        .displayName("Connection")
        .description("Shows whether the device is online, over what, and whether a VPN is active. Opens the overview.")
    }
}

struct OpenPageConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Open in Pingscape"

    @Parameter(title: "Page", default: .ping)
    var page: AppPage
}

/// Opens a tool or tab of the app, chosen when adding the control.
struct OpenPageControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "app.pingscape.control.page", intent: OpenPageConfiguration.self) {
            configuration in
            ControlWidgetButton(action: OpenURLIntent(configuration.page.url)) {
                Label(configuration.page.title, systemImage: configuration.page.symbol)
            }
        }
        .displayName("Open in Pingscape")
        .description("Opens a tool or a tab of Pingscape, such as Ping or the LAN list.")
        .promptsForUserConfiguration()
    }
}
