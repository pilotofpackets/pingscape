import SwiftUI

struct AboutView: View {
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
        }
    }
}
