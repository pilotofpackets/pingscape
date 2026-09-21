import NetKit
import SwiftUI

struct AboutView: View {
    @Environment(SnapshotStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(LANModel.self) private var lan
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PrivacyMask.hideByDefaultKey) private var hideByDefault = false

    private static let repository = URL(string: "https://github.com/pilotofpackets/pingscape")!
    private static let issues = URL(string: "https://github.com/pilotofpackets/pingscape/issues")!
    private static let license = URL(string: "https://github.com/pilotofpackets/pingscape/blob/main/LICENSE")!
    private static let privacy = URL(string: "https://github.com/pilotofpackets/pingscape/blob/main/PRIVACY.md")!

    private var version: String { "\(DeviceInfo.appVersion) (\(DeviceInfo.appBuild))" }

    var body: some View {
        @Bindable var settings = settings
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
                Section {
                    Toggle("External requests", isOn: $settings.externalLookups)
                    Toggle("Hide values by default", isOn: $hideByDefault)
                    Picker("Units", selection: $settings.rateUnit) {
                        Text("Mbit/s").tag(RateUnit.megabitPerSecond)
                        Text("MB/s").tag(RateUnit.megabytePerSecond)
                    }
                } header: {
                    Text("Settings")
                } footer: {
                    Text("External requests load your public IP address, its reverse DNS name and the provider (ipify, RIPEstat). They are off until you allow them.")
                }
                permissions
                Section("More") {
                    NavigationLink("Diagnostic dump") { DiagnosticDumpView() }
                    NavigationLink("Licenses and sources") { LicensesView() }
                }
                Section("Project") {
                    Link("Source code on GitHub", destination: Self.repository)
                    Link("Report an issue", destination: Self.issues)
                    Link("Privacy", destination: Self.privacy)
                    Link(destination: Self.license) {
                        LabeledContent("License", value: "MIT")
                    }
                }
                Section("Privacy") {
                    Text("Everything runs on your device. Requests to the internet happen only when you allow or start them, and only to the servers listed under Licenses and sources.")
                }
            }
            .navigationTitle("About")
            .onChange(of: scenePhase) { _, phase in
                // The user may have changed a permission in Settings.
                if phase == .active {
                    store.location.refresh()
                    Task { await lan.recheckAccess() }
                }
            }
        }
    }

    // MARK: Permissions

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    @ViewBuilder
    private var permissions: some View {
        Section {
            let state = store.location.state
            LabeledContent("Location") {
                switch state {
                case .authorized: Text("Allowed")
                case .denied: Text("Not allowed")
                case .notDetermined: Text("Not asked yet")
                }
            }
            switch state {
            case .authorized: EmptyView()
            case .denied: Button("Open Settings", action: openSettings)
            case .notDetermined: Button("Allow") { store.location.request() }
            }

            LabeledContent("Local network") {
                switch lan.access {
                case .allowed?: Text("Allowed")
                case .denied?: Text("Not allowed")
                default: Text("Not asked yet")
                }
            }
            if lan.access == .denied { Button("Open Settings", action: openSettings) }

            LabeledContent("External requests") {
                Text(settings.externalLookups ? "On" : "Off")
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Location is only needed to read the name of your Wi-Fi network. Pingscape does not use your location. The local network is asked for when you first search for devices.")
        }
    }
}

/// The raw data of the collectors as JSON, for a report about a wrong reading.
struct DiagnosticDumpView: View {
    @Environment(SnapshotStore.self) private var store
    @State private var anonymize = true
    @State private var text = ""
    @State private var file: URL?

    var body: some View {
        List {
            Section {
                Toggle("Replace addresses and names", isOn: $anonymize)
            } footer: {
                Text("Attach the file to an issue when Pingscape shows something wrong, for example the VPN state. With the switch on, addresses, the network name and names are replaced. The kind of address, the prefix length and which addresses belong together stay, so the reading can be checked.")
            }
            Section {
                Button {
                    Pasteboard.copy(text)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if let file {
                    ShareLink(item: file) {
                        Label("Share as file", systemImage: "square.and.arrow.up")
                    }
                }
            }
            Section("Content") {
                Text(verbatim: text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Diagnostic dump")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: anonymize) { build() }
    }

    private func build() {
        guard let snapshot = store.snapshot else { return }
        let dump = DiagnosticDump(
            snapshot: snapshot, app: .init(version: DeviceInfo.appVersion, build: DeviceInfo.appBuild),
            device: .init(model: DeviceInfo.modelIdentifier, os: DeviceInfo.systemVersion), anonymize: anonymize)
        guard let data = try? dump.json() else { return }
        text = String(decoding: data, as: UTF8.self)
        // The file lives in the temporary folder and is not kept.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let stamp = formatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pingscape-diagnostic-\(stamp).json")
        try? data.write(to: url, options: .atomic)
        file = url
    }
}

/// Where data comes from and under which terms.
struct LicensesView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Text("Pingscape is open source under the MIT License.")
            }
            Section("Data") {
                source("IEEE OUI list", detail: "Vendor names for MAC address prefixes. IEEE Registration Authority.", url: "https://standards-oui.ieee.org")
                source("RIPEstat", detail: "Provider and organization of the public IP address. Network data: RIPEstat, RIPE NCC.", url: "https://stat.ripe.net")
                source("ipify", detail: "Your public IP address (api.ipify.org, api6.ipify.org).", url: "https://www.ipify.org")
                source("IANA RDAP bootstrap", detail: "Which registry answers for a domain, address or AS number (data.iana.org).", url: "https://data.iana.org/rdap/")
            }
            Section {
                Text("Pingscape uses only the frameworks of iOS. There are no third-party libraries.")
            }
        }
        .navigationTitle("Licenses and sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func source(_ name: String, detail: LocalizedStringResource, url: String) -> some View {
        Button {
            if let url = URL(string: url) { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).foregroundStyle(.primary)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
