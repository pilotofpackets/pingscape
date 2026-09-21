import AppIntents
import Foundation
import NetKit

// Shortcuts and Siri. The actions only read: they run when the user starts
// them, return a value and change nothing. No widget or background task
// polls the network on its own.

private func currentSnapshot() async -> NetworkSnapshot {
    await LiveSnapshotProvider(locationAuthorized: { LocationAccess.isAuthorized }).snapshot()
}

struct NetworkStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Network status"
    static let description = IntentDescription(
        "Reads the state of the network right now and returns it as text: connection, Wi-Fi, VPN and cellular. Nothing is changed or sent anywhere.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let snapshot = await currentSnapshot()
        let text = StatusText.make(snapshot)
        let summary = snapshot.isOnline
            ? String(localized: "Online via \(snapshot.connectionKind.label)")
            : String(localized: "Offline")
        return .result(value: text, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct VPNActiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Is a VPN active?"
    static let description = IntentDescription("Tells whether a VPN tunnel is active on this device right now.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let active = await currentSnapshot().isVPNActive
        return .result(
            value: active,
            dialog: IntentDialog(stringLiteral: active ? String(localized: "A VPN is active") : String(localized: "No VPN is active")))
    }
}

struct PingIntent: AppIntent {
    static let title: LocalizedStringResource = "Ping a host"
    static let description = IntentDescription("Sends echo requests to a host and returns the round trip in milliseconds.")
    static let openAppWhenRun = false

    @Parameter(title: "Host", description: "A host name or IP address")
    var host: String

    static var parameterSummary: some ParameterSummary { Summary("Ping \(\.$host)") }

    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case invalidHost, cannotResolve, noReply

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .invalidHost: "This is not a valid host name or IP address"
            case .cannotResolve: "Name could not be resolved"
            case .noReply: "No answer within the time limit"
            }
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard let name = try? ToolInput.host(host) else { throw Failure.invalidHost }
        guard let address = try await HostResolver.resolve(name).first else { throw Failure.cannotResolve }
        var settings = PingSettings()
        settings.timeoutSeconds = 2
        for await event in PingTool.run(address: address, settings: settings) {
            switch event {
            case .reply(_, _, let milliseconds, _):
                let rounded = (milliseconds * 10).rounded() / 10
                return .result(value: rounded, dialog: IntentDialog(stringLiteral: String(localized: "\(host): \(Int(milliseconds.rounded())) ms")))
            case .noReply, .failed:
                throw Failure.noReply
            case .started:
                continue
            }
        }
        throw Failure.noReply
    }
}

struct PingscapeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NetworkStatusIntent(),
            phrases: ["Network status in \(.applicationName)", "\(.applicationName) network status"],
            shortTitle: "Network status", systemImageName: "network")
        AppShortcut(
            intent: VPNActiveIntent(),
            phrases: ["Is a VPN active in \(.applicationName)", "\(.applicationName) VPN status"],
            shortTitle: "Is a VPN active?", systemImageName: "lock.shield")
        AppShortcut(
            intent: PingIntent(),
            phrases: ["Ping a host with \(.applicationName)"],
            shortTitle: "Ping a host", systemImageName: "dot.radiowaves.left.and.right")
    }
}
