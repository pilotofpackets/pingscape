import NetKit
import SwiftUI

@main
struct PingscapeApp: App {
    @State private var store: SnapshotStore
    @State private var privacy = PrivacyMask()
    @State private var settings: AppSettings
    @State private var external: ExternalStore
    @State private var navigation = AppNavigation()
    @State private var lan = LANModel()

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _external = State(initialValue: ExternalStore(settings: settings))

        // `-demo` serves fixtures instead of the device state, for previews,
        // screenshots and the simulator (which shows the Mac's network).
        let provider: any NetworkSnapshotProviding =
            ProcessInfo.processInfo.arguments.contains("-demo")
            ? DemoSnapshotProvider()
            : LiveSnapshotProvider(locationAuthorized: { LocationAccess.isAuthorized })
        _store = State(initialValue: SnapshotStore(provider: provider))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(privacy)
                .environment(settings)
                .environment(external)
                .environment(navigation)
                .environment(lan)
                .task { await store.run() }
        }
    }
}
