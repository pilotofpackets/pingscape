import AppIntents
import SwiftUI

/// How Siri, the Shortcuts actions, the widgets and the Control Center
/// controls work. The action names come from the actions themselves, so they
/// read the same as in the Shortcuts app.
struct ShortcutsHelpView: View {
    private struct Action: Identifiable {
        let title: LocalizedStringResource
        let symbol: String
        var id: String { title.key }
    }

    private static let values: [Action] = [
        Action(title: GetNetworkValueIntent.title, symbol: "list.bullet.rectangle"),
        Action(title: GetNetworkDetailsIntent.title, symbol: "rectangle.stack"),
        Action(title: NetworkStatusIntent.title, symbol: "network"),
        Action(title: VPNActiveIntent.title, symbol: "lock.shield"),
    ]

    private static let tools: [Action] = [
        Action(title: PingIntent.title, symbol: "dot.radiowaves.left.and.right"),
        Action(title: DNSLookupIntent.title, symbol: "server.rack"),
        Action(title: CheckPortIntent.title, symbol: "door.left.hand.open"),
        Action(title: CertificateExpiryIntent.title, symbol: "lock.doc"),
        Action(title: HTTPCheckIntent.title, symbol: "stopwatch"),
        Action(title: TracerouteIntent.title, symbol: "point.topleft.down.to.point.bottomright.curvepath"),
        Action(title: PathMTUIntent.title, symbol: "ruler"),
        Action(title: ClockOffsetIntent.title, symbol: "clock"),
    ]

    var body: some View {
        List {
            Section {
                Text("Pingscape works with Siri, the Shortcuts app, widgets and Control Center. Nothing runs in the background: an action measures once when it runs and returns what it measured.")
            }

            Section {
                phrase("“What is my IP address in Pingscape”")
                phrase("“Wi-Fi name in Pingscape”")
                phrase("“Is a VPN active in Pingscape”")
                phrase("“Ping a host with Pingscape”")
                phrase("“Check the clock with Pingscape”")
            } header: {
                Text("Ask Siri")
            } footer: {
                Text("Instead of the IP address you can ask for any network value, such as the gateway, the DNS servers or the public IP address. If Siri needs a host, it asks for one. The Shortcuts app lists all phrases.")
            }

            Section {
                ForEach(Self.values) { row($0) }
            } header: {
                Text("Network values")
            } footer: {
                Text("“Get network value” returns one value you choose. “Get network details” returns all of them at once; choose the one you need in the next action.")
            }

            Section {
                ForEach(Self.tools) { row($0) }
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } header: {
                Text("Tools")
            } footer: {
                Text("In the Shortcuts app, search for Pingscape when you add an action. Each action returns its result, so the next action can use it, for example in a notification or an If.")
            }

            Section("Ideas") {
                idea("wifi", "When you join a Wi-Fi network: “Is a VPN active?”, and a notification if none is.")
                idea("calendar", "Every Monday: “Days until a certificate expires” for your website, and a message if fewer than 14 are left.")
                idea("doc.on.doc", "On the home screen: a shortcut that copies your IP address.")
            }

            Section {
                Text("**Network values:** up to four values you choose, on the home screen or the lock screen. Touch and hold the widget and choose Edit Widget to pick them.")
                Text("**Ping:** the round trip to a host you enter, or to the default gateway if you leave it empty.")
                Text("**↻** reads the widget again. Otherwise iOS refreshes widgets on its own schedule, at most about every 15 minutes.")
                Text("**Control Center:** open Control Center, tap +, then Add a Control, and search for Pingscape. One control shows the connection, the other opens a tab or tool you choose.")
            } header: {
                Text("Widgets and Control Center")
            } footer: {
                Text("To add a widget, touch and hold the home screen, tap Edit, then Add Widget, and search for Pingscape.")
            }

            Section {
                Text("Actions that return addresses or network names only run when the device is unlocked.")
                Text("With “Hide values by default” on, Siri says a placeholder instead of an address or name. The shortcut still gets the real value, as Copy does in the app.")
                Text("The public IP address and the provider are only loaded when external requests are on.")
                Text("Widgets hide addresses and names while the device is locked.")
                Text("The Wi-Fi name, the BSSID and the Wi-Fi security need the location permission, in Siri and the widgets as well.")
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Shortcuts and Siri")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func phrase(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "waveform")
        }
    }

    private func row(_ action: Action) -> some View {
        Label {
            Text(action.title)
        } icon: {
            Image(systemName: action.symbol)
        }
    }

    private func idea(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
        }
    }
}
