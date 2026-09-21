import NetKit
import SwiftUI

/// Devices on the local network. The search starts only when the user taps
/// "Search", never when the tab opens: the first search is what asks for the
/// Local Network permission.
struct LANView: View {
    @Environment(SnapshotStore.self) private var store
    @Environment(LANModel.self) private var lan
    @Environment(PrivacyMask.self) private var mask
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var path: [String] = DemoLaunch.value(after: "-demo-lan-device").map { [$0] } ?? []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 20) {
                    if let snapshot = store.snapshot {
                        if snapshot.lanRange == nil {
                            noNetwork
                        } else {
                            content(snapshot)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("LAN")
            .toolbar { toolbar }
            .navigationDestination(for: String.self) { ip in
                LANDeviceView(ip: ip)
            }
            .onChange(of: scenePhase) { _, phase in
                // iOS suspends the app in the background, and the search with it.
                if phase == .background, lan.isBusy { lan.stop() }
                if phase == .active { Task { await lan.recheckAccess() } }
            }
            .onChange(of: store.snapshot?.takenAt, initial: true) { _, _ in
                // The demo mode fills the list without a network.
                if DemoLaunch.isDemo, DemoLaunch.tab == .lan, lan.phase == .idle, let snapshot = store.snapshot {
                    lan.start(snapshot)
                }
            }
        }
    }

    // MARK: States

    private var noNetwork: some View {
        ContentUnavailableView {
            Label("No local network", systemImage: "network.slash")
        } description: {
            Text("This device has no local IPv4 address. Connect to Wi-Fi to look for devices.")
        }
        .frame(minHeight: 280)
    }

    @ViewBuilder
    private func content(_ snapshot: NetworkSnapshot) -> some View {
        if lan.access == .denied, lan.phase == .idle {
            denied
        } else {
            header(snapshot)
            if snapshot.tunnelScope == .full { tunnelNote }
            controls(snapshot)
            if lan.phase != .idle || !lan.list.devices.isEmpty { deviceList(snapshot) }
        }
    }

    private var denied: some View {
        ContentUnavailableView {
            Label("Local network is not allowed", systemImage: "lock")
        } description: {
            Text("To find devices in your network, Pingscape asks them directly. The results stay on your iPhone. Allow it in Settings.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(minHeight: 320)
    }

    private func header(_ snapshot: NetworkSnapshot) -> some View {
        InfoSection(title: "Network") {
            if let range = snapshot.lanRange {
                DataRow(label: "Network", value: range.description, monospaced: true, sensitive: true)
            }
            if let gateway = snapshot.localGateway4 {
                DataRow(label: "Default gateway", value: gateway, monospaced: true, sensitive: true)
            }
        }
    }

    private var tunnelNote: some View {
        InfoCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").foregroundStyle(.secondary).accessibilityHidden(true)
                Text("A VPN that carries all traffic is active. The local network is often not reachable then.")
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func footnote(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func controls(_ snapshot: NetworkSnapshot) -> some View {
        @Bindable var lan = lan
        VStack(spacing: 12) {
            Picker("Search mode", selection: $lan.mode) {
                Text("Quick").tag(LANScanMode.quick)
                Text("Thorough").tag(LANScanMode.thorough)
            }
            .pickerStyle(.segmented)
            .disabled(lan.isBusy)
            footnote(
                lan.mode == .quick
                    ? "Pings every address and listens for Bonjour."
                    : "Also tries a few ports on addresses that do not answer a ping, and lists open ports.")
            if lan.access == nil, !lan.isBusy, lan.list.devices.isEmpty {
                footnote(
                    "To find devices in your network, Pingscape asks them directly. iOS asks you once to allow this. The results stay on your iPhone."
                )
            }
            if lan.isBusy {
                progress
            } else {
                Button {
                    lan.start(snapshot)
                } label: {
                    Label(lan.phase == .idle ? "Search" : "Search again", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if lan.isCapped {
                footnote("The network is large. Only \(LANScanner.addressLimit) addresses around this device are searched.")
            }
            if let failure = lan.failure { ErrorLine(failure: .from(failure, target: nil)) }
            if lan.phase == .interrupted {
                footnote("The search was stopped. The list may be incomplete.")
            }
        }
    }

    private var progress: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if lan.phase == .askingPermission {
                        Text("Waiting for permission")
                    } else {
                        Text(lan.mode == .quick ? "Ping and Bonjour" : "Ping, Bonjour and ports")
                    }
                    Spacer()
                    if let progress = lan.progress, lan.phase == .searching {
                        Text("\(progress.done) / \(progress.total)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if let progress = lan.progress, lan.phase == .searching {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                } else {
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }
    }

    private func deviceList(_ snapshot: NetworkSnapshot) -> some View {
        let devices = lan.devices(thisDevice: snapshot.primaryIPv4?.ip, gateway: snapshot.localGateway4)
        return InfoSection(title: "Found (\(devices.count))") {
            ForEach(devices) { device in
                DeviceRow(
                    device: device, isThisDevice: device.ip == snapshot.primaryIPv4?.ip,
                    isGateway: device.ip == snapshot.localGateway4)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if lan.isBusy {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    lan.stop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .accessibilityLabel("Stop")
            }
        } else if !lan.list.devices.isEmpty, let snapshot = store.snapshot {
            ToolbarItem(placement: .primaryAction) {
                let devices = lan.devices(thisDevice: snapshot.primaryIPv4?.ip, gateway: snapshot.localGateway4)
                Menu {
                    ShareLink(item: LANReport.text(devices, masked: mask.isMasked)) {
                        Label("Share list", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: LANReport.csv(devices, masked: mask.isMasked)) {
                        Label("Share as CSV", systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
        }
    }
}

/// One device in the list: its name (or what is known), address and services.
private struct DeviceRow: View {
    @Environment(PrivacyMask.self) private var mask
    @Environment(AppNavigation.self) private var navigation
    let device: LANDevice
    let isThisDevice: Bool
    let isGateway: Bool

    private var title: String {
        if isThisDevice { return String(localized: "This iPhone") }
        if isGateway { return device.displayName ?? String(localized: "Router (gateway)") }
        return device.displayName ?? String(localized: "Device · answers to ping")
    }

    /// Whether the title is a name the device gave itself, which can name a person.
    private var titleIsName: Bool { !isThisDevice && device.displayName != nil }

    private var subtitle: String {
        var parts: [String] = []
        if isGateway, device.displayName != nil { parts.append(String(localized: "Router")) }
        let services = LANReport.serviceNames(device)
        if !services.isEmpty { parts.append(services.prefix(3).joined(separator: ", ")) }
        if let latency = device.latencyMilliseconds { parts.append(milliseconds(latency)) }
        return parts.joined(separator: " · ")
    }

    private var symbol: String? {
        isThisDevice ? "iphone" : (isGateway ? "wifi.router" : nil)
    }

    private var shownTitle: String { titleIsName ? mask.shown(title) : title }

    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleBlock
                    Spacer(minLength: 8)
                    address
                }
                VStack(alignment: .leading, spacing: 2) {
                    titleBlock
                    address
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !isThisDevice {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(shownTitle)
            if !subtitle.isEmpty {
                Text(verbatim: subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var address: some View {
        Text(mask.shown(device.ip))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    var body: some View {
        Group {
            if isThisDevice {
                Button {
                    navigation.openOverview(.wifi)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: device.ip) { content }
                    .buttonStyle(.plain)
            }
        }
        .contextMenu { RowCopyMenu(value: device.ip) }
        .accessibilityElement(children: .combine)
        // What is on screen: hidden names and addresses stay hidden in a copy.
        .recordRow(label: LocalizedStringResource(stringLiteral: shownTitle), value: mask.shown(device.ip))
    }
}
