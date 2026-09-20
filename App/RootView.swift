import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SnapshotStore.self) private var store

    var body: some View {
        TabView {
            Tab("Overview", systemImage: "square.grid.2x2") { StatusView() }
            Tab("LAN", systemImage: "network") {
                PlaceholderView(title: "LAN", systemImage: "network")
            }
            Tab("Live", systemImage: "waveform.path.ecg") {
                PlaceholderView(title: "Live", systemImage: "waveform.path.ecg")
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver") {
                PlaceholderView(title: "Tools", systemImage: "wrench.and.screwdriver")
            }
            Tab("About", systemImage: "info.circle") { AboutView() }
        }
        .modifier(MinimizeTabBarOnScroll())
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }
}

/// The tab bar shrinks while scrolling (iOS 26 and later).
private struct MinimizeTabBarOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

/// Stands in for tabs that are not built yet.
struct PlaceholderView: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text("Coming soon.")
            }
            .navigationTitle(title)
        }
    }
}
