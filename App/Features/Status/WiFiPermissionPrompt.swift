import SwiftUI

/// Asks for the location permission that iOS demands before it hands out the
/// Wi-Fi name. The explanation comes first, the system dialog on tap. After a
/// refusal iOS shows no dialog again, so the button opens Settings instead.
struct WiFiPermissionPrompt: View {
    @Environment(SnapshotStore.self) private var store
    @Environment(\.openURL) private var openURL

    private var isDenied: Bool { store.location.state == .denied }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PermissionRow(
                label: "Wi-Fi name", buttonTitle: isDenied ? "Open Settings" : "Allow"
            ) {
                if isDenied {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } else {
                    store.location.request()
                }
            }
            Text("iOS only gives the name of your Wi-Fi network to apps that may use your location. Pingscape does not use your location.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }
}
