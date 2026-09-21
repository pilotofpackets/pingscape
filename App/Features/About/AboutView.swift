import SwiftUI

struct AboutView: View {
    @Environment(SnapshotStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PrivacyMask.hideByDefaultKey) private var hideByDefault = false

    private static let repository = URL(string: "https://github.com/pilotofpackets/pingscape")!
    private static let issues = URL(string: "https://github.com/pilotofpackets/pingscape/issues")!
    private static let license = URL(string: "https://github.com/pilotofpackets/pingscape/blob/main/LICENSE")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Pingscape").font(.title.bold())
                        Text("Version \(version)").foregroundStyle(.secondary)
                        Text("Open source. No account. No ads. No tracking.")
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                Section("Settings") {
                    Toggle("Hide values by default", isOn: $hideByDefault)
                }
                permissions
                Section("Project") {
                    Link("Source code on GitHub", destination: Self.repository)
                    Link("Report an issue", destination: Self.issues)
                    Link(destination: Self.license) {
                        LabeledContent("License", value: "MIT")
                    }
                }
                Section("Privacy") {
                    Text("Everything runs on your device. Nothing is collected or sent anywhere.")
                }
            }
            .navigationTitle("About")
            .onChange(of: scenePhase) { _, phase in
                // The user may have changed the permission in Settings.
                if phase == .active { store.location.refresh() }
            }
        }
    }

    @ViewBuilder
    private var permissions: some View {
        let state = store.location.state
        Section {
            LabeledContent("Location") {
                switch state {
                case .authorized: Text("Allowed")
                case .denied: Text("Not allowed")
                case .notDetermined: Text("Not asked yet")
                }
            }
            switch state {
            case .authorized:
                EmptyView()
            case .denied:
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .notDetermined:
                Button("Allow") { store.location.request() }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Only needed to read the name of your Wi-Fi network. Pingscape does not use your location.")
        }
    }
}
