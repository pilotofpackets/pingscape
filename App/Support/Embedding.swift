import NetKit
import SwiftUI

// Embedding in another app: instead of `PingscapeApp`, the host keeps a
// `PingscapeSession` (network state, LAN list and settings survive closing) and
// shows `PingscapeView` full screen. The Swift package at the repository root
// exposes this as the `PingscapeUI` library.
//
// `Text` looks up strings in the host's main bundle, so the host's catalog has to
// contain the keys of App/Resources/Localizable.xcstrings.

/// The state `PingscapeApp` otherwise creates itself.
@MainActor
public final class PingscapeSession {
    let store: SnapshotStore
    let privacy = PrivacyMask()
    let settings: AppSettings
    let external: ExternalStore
    let navigation = AppNavigation()
    let lan = LANModel()

    /// `demo` provides the sample data instead of the device state (simulator, screenshots).
    public init(demo: Bool) {
        let settings = AppSettings()
        self.settings = settings
        external = ExternalStore(settings: settings)
        let provider: any NetworkSnapshotProviding =
            demo ? DemoSnapshotProvider() : LiveSnapshotProvider(locationAuthorized: { LocationAccess.isAuthorized })
        store = SnapshotStore(provider: provider)
    }

    /// Skips the introduction on first launch. The question about external lookups
    /// stays, and the introduction can still be opened from About.
    public func skipIntroduction() {
        if !settings.onboardingShown { settings.onboardingShown = true }
    }
}

/// Pingscape with all tabs; `close` adds a close button to each tab.
public struct PingscapeView: View {
    private let session: PingscapeSession
    private let close: @MainActor @Sendable () -> Void

    public init(session: PingscapeSession, close: @escaping @MainActor @Sendable () -> Void) {
        self.session = session
        self.close = close
    }

    public var body: some View {
        RootView()
            .environment(session.store)
            .environment(session.privacy)
            .environment(session.settings)
            .environment(session.external)
            .environment(session.navigation)
            .environment(session.lan)
            .environment(\.pingscapeClose, CloseAction(run: close))
            .task { await session.store.run() }
    }
}

/// Like `DismissAction`: comparable, so the environment does not redraw on every update.
struct CloseAction: Equatable, Sendable {
    private let id = UUID()
    let run: @MainActor @Sendable () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension EnvironmentValues {
    @Entry var pingscapeClose: CloseAction? = nil
}

private struct CloseButton: ViewModifier {
    @Environment(\.pingscapeClose) private var close

    func body(content: Content) -> some View {
        content.toolbar {
            if let close {
                ToolbarItem(placement: .topBarLeading) {
                    Group {
                        if #available(iOS 26.0, *) {
                            Button(role: .close) { close.run() }
                        } else {
                            Button("Close", systemImage: "xmark") { close.run() }
                        }
                    }
                    .accessibilityIdentifier("pingscape.close")
                }
            }
        }
    }
}

extension View {
    /// Closes the embedded app. Invisible without a host.
    func pingscapeCloseButton() -> some View {
        modifier(CloseButton())
    }
}

extension Bundle {
    /// Where assets and data files live: the app, or the package's bundle when embedded.
    static var pingscapeResources: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}
