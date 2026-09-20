import NetKit
import SwiftUI

@main
struct PingscapeApp: App {
    @State private var store: SnapshotStore
    @State private var privacy = PrivacyMask()

    init() {
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
                .task { await store.run() }
        }
    }
}
