import SwiftUI

enum AppTab: String, Hashable {
    case overview, lan, live, tools, about
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SnapshotStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(ExternalStore.self) private var external
    @Environment(AppNavigation.self) private var navigation
    @State private var showsExternalPrompt = false

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
            Tab("Overview", systemImage: "square.grid.2x2", value: AppTab.overview) { StatusView() }
            Tab("LAN", systemImage: "network", value: AppTab.lan) { LANView() }
            Tab("Live", systemImage: "waveform.path.ecg", value: AppTab.live) {
                LiveView(isVisible: navigation.tab == .live && scenePhase == .active)
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver", value: AppTab.tools) { ToolsView() }
            Tab("About", systemImage: "info.circle", value: AppTab.about) { AboutView() }
        }
        .modifier(MinimizeTabBarOnScroll())
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.refresh() }
            external.load()
        }
        // A new network usually means a new public address.
        .onChange(of: store.pathChanges) { _, _ in external.load() }
        .onChange(of: settings.externalLookups) { _, isOn in
            if isOn { external.load(force: true) } else { external.reset() }
        }
        .task {
            if !settings.externalPromptShown, !DemoLaunch.isDemo || DemoLaunch.value(after: "-demo-firstrun") != nil {
                showsExternalPrompt = true
            }
            external.load()
        }
        .sheet(isPresented: $showsExternalPrompt) {
            ExternalPromptSheet()
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

/// The one question at first launch: may the app ask the internet for the
/// public address and the provider? Asked once, and it can be changed under About.
struct ExternalPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "globe")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Show public IP and provider?")
                    .font(.title2.bold())
                Text(
                    "For this, Pingscape asks two services on the internet: one for your public IP address and RIPEstat (RIPE NCC) for the provider and organization. Only your public IP address is sent. There is no server of ours. You can change this at any time under About."
                )
                .foregroundStyle(.secondary)
                Button {
                    settings.externalLookups = true
                    settings.externalPromptShown = true
                    dismiss()
                } label: {
                    Text("Yes, show").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button {
                    settings.externalPromptShown = true
                    dismiss()
                } label: {
                    Text("Not now").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
}
