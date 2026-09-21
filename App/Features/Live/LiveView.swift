import Charts
import NetKit
import SwiftUI

/// Throughput, latency and events while the tab is open. Runs only in the
/// foreground and only in memory.
struct LiveView: View {
    let isVisible: Bool

    @Environment(SnapshotStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(PrivacyMask.self) private var mask
    @State private var model = LiveModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let snapshot = store.snapshot {
                        content(snapshot)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .readableContentWidth()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Live")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { runState }
            }
        }
    }

    private var runState: some View {
        HStack(spacing: 6) {
            StatusDot(tone: isVisible || DemoLaunch.isDemo ? .good : .neutral)
            Text(isVisible || DemoLaunch.isDemo ? "Running" : "Paused")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(_ snapshot: NetworkSnapshot) -> some View {
        let interfaces = model.interfaces(in: snapshot)
        let selected = model.selected(in: snapshot)
        let gateway = model.gatewayTarget(in: snapshot, interface: selected)
        let pingTargets = pingTargets(gateway: gateway)
        Group {
            if interfaces.isEmpty {
                ContentUnavailableView {
                    Label("No connection to watch", systemImage: "waveform.path.ecg")
                } description: {
                    Text("Live values appear as soon as the device has a Wi-Fi, cellular or VPN connection.")
                }
                .frame(minHeight: 280)
            } else {
                if interfaces.count > 1 { picker(interfaces, selected: selected) }
                throughput
                latencySection(target: pingTargets.first)
                timeline
            }
        }
        // Throughput of the shown interface, once a second.
        .task(id: TaskKey(visible: isVisible, name: selected?.name)) {
            guard isVisible, let name = selected?.name else { return }
            model.resetThroughput()
            await model.sample(interface: name)
        }
        // Latency to the router or the internet target.
        .task(id: TaskKey(visible: isVisible, name: pingTargets.first)) {
            guard isVisible else { return }
            model.resetLatency()
            if let target = pingTargets.first { await model.ping(target) }
        }
        // The events (radio technology, access point) need fresh snapshots.
        .task(id: isVisible) {
            guard isVisible, !DemoLaunch.isDemo else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await store.refresh()
            }
        }
    }

    private struct TaskKey: Hashable {
        let visible: Bool
        let name: String?
    }

    /// The router when there is one, and the internet host if the user asked for it.
    private func pingTargets(gateway: String?) -> [String] {
        var targets: [String] = []
        if model.usesInternetTarget, let host = try? ToolInput.host(model.internetHost) {
            targets.append(host)
        } else if let gateway {
            targets.append(gateway)
        }
        return targets
    }

    // MARK: Pieces

    private func picker(_ interfaces: [LiveInterface], selected: LiveInterface?) -> some View {
        Picker(
            "Connection",
            selection: Binding(get: { selected?.name ?? "" }, set: { model.picked = $0 })
        ) {
            ForEach(interfaces) { Text(verbatim: $0.title).tag($0.name) }
        }
        .pickerStyle(.segmented)
    }

    private var throughput: some View {
        VStack(spacing: 12) {
            ChartCard(
                title: "Receive", points: model.receive, style: .rate(settings.rateUnit), tint: .accentColor)
            ChartCard(title: "Send", points: model.send, style: .rate(settings.rateUnit), tint: .secondary)
        }
    }

    private func latencySection(target: String?) -> some View {
        @Bindable var model = model
        return VStack(spacing: 12) {
            if target != nil || model.usesInternetTarget || DemoLaunch.isDemo {
                ChartCard(title: "Latency", points: model.latencyPoints, style: .latency, tint: .accentColor)
                InfoSection(title: "Quality") {
                    DataRow(label: "Latency", value: model.latency.latest.map(milliseconds) ?? "–")
                    DataRow(label: "Jitter", value: model.latency.jitter.map(milliseconds) ?? "–")
                    DataRow(
                        label: "Loss",
                        value: model.latency.lostPercent.map { "\(Int($0.rounded())) %" } ?? "–")
                }
            }
            InfoCard {
                Toggle("Ping a host on the internet", isOn: $model.usesInternetTarget)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                if model.usesInternetTarget {
                    TextField("Host", text: $model.internetHost)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                }
            }
            if model.usesInternetTarget, let host = try? ToolInput.host(model.internetHost) {
                Text("Pings \(host) once a second. That host sees your public IP address.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        let entries = DemoLaunch.isDemo ? Self.demoTimeline : store.timeline.entries
        if !entries.isEmpty {
            InfoSection(title: "Timeline") {
                ForEach(entries) { entry in
                    let text = entry.change.text
                    DataRow(
                        label: LocalizedStringResource(stringLiteral: entry.time.formatted(date: .omitted, time: .shortened)),
                        value: text.value, monospaced: text.sensitive, sensitive: text.sensitive, stacked: true)
                }
            }
        }
    }

    private static let demoTimeline: [TimelineEntry] = {
        let now = Date()
        return [
            TimelineEntry(id: 3, time: now.addingTimeInterval(-120), change: .radio(from: .lte, to: .nrNonStandalone, isDataService: true)),
            TimelineEntry(id: 2, time: now.addingTimeInterval(-300), change: .connection(from: .wifi, to: .cellular)),
            TimelineEntry(id: 1, time: now.addingTimeInterval(-900), change: .vpn(isActive: true)),
        ]
    }()
}

/// A number and its chart.
private struct ChartCard: View {
    enum Style {
        case rate(RateUnit)
        case latency

        func text(_ value: Double) -> String {
            switch self {
            case .rate(let unit): unit.string(bytesPerSecond: value)
            case .latency: milliseconds(value)
            }
        }
    }

    let title: LocalizedStringResource
    let points: [LivePoint]
    let style: Style
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(points.last.map { style.text($0.value) } ?? "–")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Chart(points) { point in
                AreaMark(x: .value("Time", point.time), y: .value("Value", point.value))
                    .foregroundStyle(tint.opacity(0.15))
                LineMark(x: .value("Time", point.time), y: .value("Value", point.value))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...max(points.map(\.value).max() ?? 1, 1))
            .frame(height: 72)
            .accessibilityHidden(true)
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(points.last.map { style.text($0.value) } ?? "–"))
    }
}
