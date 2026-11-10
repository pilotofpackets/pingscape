import NetKit
import SwiftUI

// One view per tool. Each shows a field, a line about where the request goes,
// and the result as sections. The sections report themselves, so the toolbar
// can copy or share them.

private let dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)

// MARK: Ping

struct PingView: View {
    @Bindable var model: PingModel
    let history: ToolHistory
    @Environment(PrivacyMask.self) private var mask

    var body: some View {
        VStack(spacing: 16) {
            ToolField(title: "Host or IP address", text: $model.input) { model.start() }
            RecentChips(items: history.recent(.ping)) { model.input = $0 }
            Picker("Mode", selection: $model.mode) {
                Text("Ping").tag(PingMode.ping)
                Text("Path MTU").tag(PingMode.pathMTU)
            }
            .pickerStyle(.segmented)
            .disabled(model.isRunning)
            switch model.mode {
            case .ping:
                options
                ToolNote(
                    Text("Sends echo requests until you stop it.")
                        + Text(verbatim: model.packetSizeText.map { " \($0)." } ?? ""))
            case .pathMTU:
                ToolNote(Text("Finds the largest packet that reaches the target and comes back unfragmented, with \"don't fragment\" set."))
            }
            if let failure = model.failure { ErrorLine(failure: failure) }
            if model.offersFamilyChoice, let current = model.current {
                Picker("Address family", selection: Binding(get: { current.isIPv6 }, set: { model.select(ipv6: $0) })) {
                    Text("IPv4").tag(false)
                    Text("IPv6").tag(true)
                }
                .pickerStyle(.segmented)
            }
            switch model.mode {
            case .ping:
                if model.statistics.sent > 0 { summary }
                if !model.lines.isEmpty { replies }
            case .pathMTU:
                if model.current != nil, model.interfaceName != nil || !model.probes.isEmpty { mtuResult }
                if !model.probes.isEmpty { mtuProbes }
            }
        }
    }

    /// Packet size and "don't fragment". They apply from the next start.
    private var options: some View {
        InfoCard {
            HStack(spacing: 8) {
                Text("Payload")
                Spacer(minLength: 8)
                TextField(text: $model.payloadText, prompt: Text(verbatim: "56")) { Text("Payload") }
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 90)
                Text("bytes").foregroundStyle(.secondary)
                Menu {
                    Button("Default (56 bytes payload)") { model.payloadText = "" }
                    Button("1280-byte packet (IPv6 minimum)") { model.setPacketSize(1280) }
                    Button("1500-byte packet (Ethernet)") { model.setPacketSize(1500) }
                    Button("9000-byte packet (jumbo frame)") { model.setPacketSize(9000) }
                } label: {
                    Image(systemName: "list.bullet.circle")
                        .imageScale(.large)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Packet sizes")
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .frame(minHeight: 44)
            Toggle("Don't fragment", isOn: $model.dontFragment)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
        }
        .disabled(model.isRunning)
    }

    private var mtuResult: some View {
        InfoSection(title: "Path MTU") {
            if let address = model.current {
                DataRow(label: "Address", value: address.text, monospaced: true, sensitive: true)
            }
            if let name = model.interfaceName {
                DataRow(
                    label: "Interface",
                    value: model.interfaceMTU.map { String(localized: "\(name) · MTU \(String($0))") } ?? name)
            }
            if case .some(let found) = model.pathMTU {
                if let found, let address = model.current {
                    DataRow(label: "Path MTU", value: byteCount(found))
                    DataRow(
                        label: "Largest payload",
                        value: byteCount(found - PingSettings.headerSize(ipv6: address.isIPv6)))
                    if let interfaceMTU = model.interfaceMTU, interfaceMTU > found {
                        DataRow(label: "Below interface MTU", value: byteCount(interfaceMTU - found))
                    }
                    if let router = limitingRouter {
                        DataRow(label: "Limit reported by", value: router, monospaced: true, sensitive: true)
                    } else if model.probes.contains(where: { $0.result == .noReply }) {
                        DataRow(label: "Larger packets", value: String(localized: "Dropped without a message"))
                    }
                } else {
                    DataRow(label: "Result", value: String(localized: "The target does not answer echo requests"))
                }
            }
        }
    }

    /// The router that named the limit, from the "too big" message of the search.
    private var limitingRouter: String? {
        for probe in model.probes.reversed() {
            if case .tooBig(_, let router) = probe.result { return router }
        }
        return nil
    }

    private var mtuProbes: some View {
        InfoSection(title: "Probes") {
            ForEach(model.probes) { probe in
                DataRow(
                    label: LocalizedStringResource(stringLiteral: byteCount(probe.packetSize)),
                    value: text(probe.result))
            }
        }
    }

    private func text(_ result: PathMTUProbe.Result) -> String {
        switch result {
        case .passed(let ms): String(localized: "Passed · \(milliseconds(ms))")
        case .tooBig(let mtu?, let router): String(localized: "Too big · \(mask.shown(router)) reports MTU \(String(mtu))")
        case .tooBig(nil, let router): String(localized: "Too big · reported by \(mask.shown(router))")
        case .tooBigToSend: String(localized: "Too big to send from this device")
        case .noReply: String(localized: "No reply")
        }
    }

    private var summary: some View {
        let stats = model.statistics
        return InfoSection(title: "Summary") {
            if let address = model.current {
                DataRow(label: "Address", value: address.text, monospaced: true, sensitive: true)
            }
            if case .tcp(let port)? = model.method {
                DataRow(label: "Method", value: String(localized: "TCP ping, port \(Int(port))"))
            } else if model.method == .icmp {
                DataRow(label: "Method", value: "ICMP")
            }
            DataRow(
                label: "Payload",
                value: byteCount(model.settings.payloadSize)
                    + (model.settings.dontFragment ? " · " + String(localized: "don't fragment") : ""))
            DataRow(label: "Sent", value: String(stats.sent))
            DataRow(label: "Received", value: String(stats.received))
            DataRow(label: "Loss", value: "\(Int(stats.lostPercent.rounded())) %")
            if let minimum = stats.minimum, let average = stats.average, let maximum = stats.maximum {
                DataRow(label: "Min · Avg · Max", value: "\(milliseconds(minimum)) · \(milliseconds(average)) · \(milliseconds(maximum))")
            }
            if let jitter = stats.jitter { DataRow(label: "Jitter", value: milliseconds(jitter)) }
        }
    }

    private var replies: some View {
        InfoSection(title: "Replies") {
            ForEach(model.lines.suffix(100).reversed()) { line in
                DataRow(label: LocalizedStringResource(stringLiteral: "#\(line.id)"), value: text(line))
            }
        }
    }

    private func text(_ line: PingLine) -> String {
        switch line.kind {
        case .reply(let bytes, let ms, let ttl):
            [bytes.map(byteCount), milliseconds(ms), ttl.map { "TTL \($0)" }]
                .compactMap { $0 }.joined(separator: " · ")
        case .noReply: String(localized: "No reply")
        case .failed(let error): error.text
        case .tooBig(let mtu?, let router?): String(localized: "Too big · \(mask.shown(router)) reports MTU \(String(mtu))")
        case .tooBig(nil, let router?): String(localized: "Too big · reported by \(mask.shown(router))")
        case .tooBig(_, nil): String(localized: "Too big to send from this device")
        }
    }
}

// MARK: Traceroute

struct TracerouteView: View {
    @Bindable var model: TracerouteModel
    let history: ToolHistory

    var body: some View {
        VStack(spacing: 16) {
            ToolField(title: "Host or IP address", text: $model.input) { model.start() }
            RecentChips(items: history.recent(.traceroute)) { model.input = $0 }
            Picker("Mode", selection: $model.mode) {
                Text("Once").tag(TracerouteMode.once)
                Text("Continuous (MTR)").tag(TracerouteMode.continuous)
            }
            .pickerStyle(.segmented)
            .disabled(model.isRunning)
            InfoCard {
                Toggle("Look up names", isOn: $model.resolveNames)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
            }
            .disabled(model.isRunning)
            if model.mode == .continuous {
                ToolNote(Text("Sends one echo request to every hop each second until you stop it, and keeps loss and times per hop."))
            }
            ToolNote(Text("Names come from your DNS server, which then sees the addresses of the routers on the way."))
            if let failure = model.failure { ErrorLine(failure: failure) }
            if model.mode == .continuous {
                if !model.mtrHops.isEmpty { continuous }
            } else if !model.hops.isEmpty {
                InfoSection(title: "Route") {
                    ForEach(model.hops) { hop in
                        HopRow(hop: hop, name: model.names[hop.number])
                    }
                    if let reached = model.reachedTarget {
                        DataRow(
                            label: "Result",
                            value: reached ? String(localized: "Target reached") : String(localized: "Target not reached"))
                    }
                }
            }
        }
    }
}

extension TracerouteView {
    /// The hops up to the last one that ever answered. Beyond it there is
    /// nothing measured to show.
    private var shownHops: [MTRHop] {
        guard let last = model.mtrHops.lastIndex(where: { $0.statistics.received > 0 }) else { return [] }
        return Array(model.mtrHops[...last])
    }

    var continuous: some View {
        InfoSection(title: "Route") {
            ForEach(shownHops) { hop in
                MTRHopRow(hop: hop, names: hop.addresses.compactMap { model.namesByAddress[$0] })
            }
            DataRow(label: "Rounds", value: String(model.mtrRounds))
            DataRow(
                label: "Result",
                value: model.mtrReached ? String(localized: "Target reached") : String(localized: "Target not reached"))
        }
    }
}

/// A hop of the continuous traceroute: its addresses, then loss and times.
private struct MTRHopRow: View {
    @Environment(PrivacyMask.self) private var mask
    let hop: MTRHop
    let names: [String]

    private var addressText: String {
        hop.addresses.isEmpty ? String(localized: "No reply") : hop.addresses.map { mask.shown($0) }.joined(separator: "\n")
    }

    private var figures: String {
        let stats = hop.statistics
        var parts = ["\(String(localized: "Loss")) \(Int(stats.lostPercent.rounded())) %"]
        if let last = hop.last { parts.append("\(String(localized: "Last")) \(milliseconds(last))") }
        if let average = stats.average { parts.append("\(String(localized: "Avg")) \(milliseconds(average))") }
        if let minimum = stats.minimum, let maximum = stats.maximum {
            parts.append("\(String(localized: "Best")) \(milliseconds(minimum))")
            parts.append("\(String(localized: "Worst")) \(milliseconds(maximum))")
        }
        if let jitter = stats.jitter { parts.append("\(String(localized: "Jitter")) \(milliseconds(jitter))") }
        // A line breaks between the figures, never inside one ("1.9 / ms").
        return parts.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: "\(hop.number)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .trailing)
                Text(addressText)
                    .font(hop.addresses.isEmpty ? .body : .system(.body, design: .monospaced))
                    .foregroundStyle(hop.addresses.isEmpty ? .secondary : .primary)
                Spacer(minLength: 8)
                if hop.statistics.lostPercent > 0 {
                    StatusDot(tone: hop.statistics.received == 0 ? .critical : .warning)
                        .accessibilityHidden(true)
                }
            }
            Text(figures)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.leading, 36)
            ForEach(names, id: \.self) { name in
                Text(mask.shown(name))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu { RowCopyMenu(value: (hop.addresses + names).joined(separator: " · ")) }
        .accessibilityElement(children: .combine)
        .recordRow(
            label: LocalizedStringResource(stringLiteral: "\(hop.number)"),
            value: ([addressText.replacingOccurrences(of: "\n", with: ", "), figures] + names.map { mask.shown($0) })
                .joined(separator: " · "))
    }
}

private struct HopRow: View {
    @Environment(PrivacyMask.self) private var mask
    let hop: TracerouteHop
    let name: String?

    private var times: String {
        hop.times.map { $0.map(milliseconds) ?? "*" }.joined(separator: "  ")
    }

    private var address: String { hop.address ?? String(localized: "No reply") }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: "\(hop.number)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .trailing)
                Text(hop.address.map { mask.shown($0) } ?? address)
                    .font(hop.address == nil ? .body : .system(.body, design: .monospaced))
                    .foregroundStyle(hop.address == nil ? .secondary : .primary)
            }
            Text(verbatim: times)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.leading, 36)
            if let name {
                Text(mask.shown(name))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu { RowCopyMenu(value: [hop.address, name].compactMap { $0 }.joined(separator: " · ")) }
        .accessibilityElement(children: .combine)
        // Shown text, so a hidden hop stays hidden in a copy.
        .recordRow(
            label: LocalizedStringResource(stringLiteral: "\(hop.number)"),
            value: [hop.address.map { mask.shown($0) } ?? address, times, name.map { mask.shown($0) }]
                .compactMap { $0 }.joined(separator: " · "))
    }
}

// MARK: DNS

struct DNSView: View {
    @Bindable var model: DNSModel
    let history: ToolHistory
    @Environment(PrivacyMask.self) private var mask

    var body: some View {
        VStack(spacing: 16) {
            ToolField(title: "Name (for PTR: an IP address)", text: $model.input) { model.start() }
            RecentChips(items: history.recent(.dns)) { model.input = $0 }
            InfoCard {
                HStack {
                    Text("Type")
                    Spacer()
                    Picker("Type", selection: $model.type) {
                        ForEach(DNSRecordType.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                HStack {
                    Text("Protocol")
                    Spacer()
                    Picker("Protocol", selection: $model.encryption) {
                        Text(verbatim: "UDP/TCP").tag(DNSEncryption.none)
                        Text("DNS over TLS").tag(DNSEncryption.tls)
                        Text("DNS over HTTPS").tag(DNSEncryption.https)
                    }
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                Toggle("Compare servers", isOn: $model.compare)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                if !model.compare {
                    HStack {
                        Text("Server")
                        Spacer()
                        Picker("Server", selection: $model.choice) {
                            if model.offersSystem { Text("System").tag(DNSServerChoice.system) }
                            Text(verbatim: "Cloudflare").tag(DNSServerChoice.cloudflare)
                            Text(verbatim: "Google").tag(DNSServerChoice.google)
                            Text(verbatim: "Quad9").tag(DNSServerChoice.quad9)
                            Text("Custom").tag(DNSServerChoice.custom)
                        }
                        .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                }
                if model.compare || model.choice == .custom {
                    TextField(customPrompt, text: $model.customServer)
                        .keyboardType(model.encryption == .none ? .numbersAndPunctuation : .URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                }
                Toggle("Request DNSSEC", isOn: $model.dnssec)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
            }
            .disabled(model.isRunning)
            if let server = model.serverText {
                ToolNote(Text("The request goes to \(model.choice == .system ? mask.shown(server) : server)"))
            } else if model.compare {
                if model.offersSystem {
                    ToolNote(Text("Asks the system's server, Cloudflare, Google, Quad9 and your own server at once."))
                } else {
                    ToolNote(Text("Asks Cloudflare, Google, Quad9 and your own server at once. The system's server is only known by its plain address."))
                }
            }
            if model.encryption != .none {
                ToolNote(Text("Each request opens a new connection, so the time includes the TCP and TLS handshakes."))
            }
            if let failure = model.failure { ErrorLine(failure: failure) }
            if let response = model.response { result(response) }
            if !model.comparison.isEmpty { comparison }
        }
    }

    private var customPrompt: LocalizedStringKey {
        switch (model.compare, model.encryption) {
        case (true, _): "Own server (optional)"
        case (false, .none): "DNS server address"
        case (false, .tls): "Server name or address"
        case (false, .https): "Server name or DoH URL"
        }
    }

    private var comparison: some View {
        VStack(spacing: 16) {
            if let agrees = model.comparisonAgrees {
                InfoSection(title: "Comparison") {
                    StatusRow(
                        label: "Answers",
                        text: agrees ? String(localized: "Same at all servers") : String(localized: "Differ between servers"),
                        tone: agrees ? .good : .warning)
                }
            }
            ForEach(model.comparison) { row in
                InfoSection(title: LocalizedStringResource(stringLiteral: title(of: row.choice))) {
                    DataRow(label: "Server", value: row.server, monospaced: true, sensitive: row.choice == .system)
                    switch row.result {
                    case .success(let response):
                        StatusRow(
                            label: "Response code", text: response.responseCodeName,
                            tone: response.responseCode == 0 ? .good : .warning)
                        DataRow(label: "Time", value: milliseconds(response.milliseconds))
                        if model.askedForDNSSEC { dnssecRow(response) }
                        DataRow(
                            label: "Records",
                            value: response.comparableAnswers.isEmpty
                                ? String(localized: "No records") : response.comparableAnswers.joined(separator: "\n"),
                            monospaced: true, stacked: true)
                    case .failure(let failure):
                        StatusRow(label: "Result", text: failure.text, tone: .critical)
                    }
                }
            }
        }
    }

    private func title(of choice: DNSServerChoice) -> String {
        switch choice {
        case .system: String(localized: "System")
        case .custom: String(localized: "Custom")
        default: choice.name ?? ""
        }
    }

    private func dnssecRow(_ response: DNSResponse) -> some View {
        DataRow(
            label: "DNSSEC",
            value: response.isAuthenticated
                ? String(localized: "Validated by the server (AD)")
                : String(localized: "Not validated by the server"))
    }

    private func result(_ response: DNSResponse) -> some View {
        VStack(spacing: 16) {
            InfoSection(title: "Response") {
                StatusRow(
                    label: "Response code", text: response.responseCodeName,
                    tone: response.responseCode == 0 ? .good : .warning)
                if !response.flags.isEmpty {
                    DataRow(label: "Flags", value: response.flags.joined(separator: " "))
                }
                DataRow(label: "Time", value: milliseconds(response.milliseconds))
                if model.askedForDNSSEC { dnssecRow(response) }
                DataRow(label: "Transport", value: response.transport.rawValue)
                DataRow(label: "Server", value: response.server, monospaced: true, sensitive: true)
            }
            InfoSection(title: "Records") {
                if response.answers.isEmpty && response.responseCode == 0 {
                    DataRow(label: "Result", value: String(localized: "No records"))
                }
                ForEach(response.answers) { record in
                    DataRow(
                        label: LocalizedStringResource(stringLiteral: "\(record.type) · \(record.name) · \(record.ttl) s"),
                        value: record.value, monospaced: true, stacked: true)
                }
            }
        }
    }
}

// MARK: Whois and RDAP

struct WhoisView: View {
    @Bindable var model: WhoisModel
    let history: ToolHistory

    var body: some View {
        VStack(spacing: 16) {
            ToolField(title: "Domain, IP address or AS number", text: $model.input) { model.start() }
            RecentChips(items: history.recent(.whois)) { model.input = $0 }
            ToolNote(Text("The name goes to the registry that is responsible for it. Registry data of others is not hidden by “Hide values”."))
            if let failure = model.failure { ErrorLine(failure: failure) }
            if model.hasResult, model.rdap == nil, model.whois.isEmpty, let failure = model.whoisFailure ?? model.rdapFailure {
                ErrorLine(failure: failure)
            }
            if let rdap = model.rdap { rdapSection(rdap) }
            if !model.whois.isEmpty { whoisSections }
        }
    }

    private func date(_ text: String) -> String {
        ISO8601DateFormatter().date(from: text).map { $0.formatted(dateStyle) } ?? text
    }

    private func rdapSection(_ rdap: RDAPResult) -> some View {
        InfoSection(title: "RDAP") {
            if let name = rdap.name { DataRow(label: "Name", value: name) }
            if let range = rdap.range { DataRow(label: "Range", value: range, monospaced: true) }
            if let registrar = rdap.registrar { DataRow(label: "Registrar", value: registrar) }
            if !rdap.status.isEmpty { DataRow(label: "Status", value: rdap.status.joined(separator: "\n")) }
            ForEach(rdap.events, id: \.action.hashValue) { event in
                DataRow(label: event.action.label, value: date(event.date))
            }
            if !rdap.nameservers.isEmpty {
                DataRow(label: "Name servers", value: rdap.nameservers.joined(separator: "\n"), monospaced: true)
            }
            if let handle = rdap.handle { DataRow(label: "Handle", value: handle, monospaced: true) }
            DataRow(label: "Source", value: rdap.server, monospaced: true)
        }
    }

    private var whoisSections: some View {
        VStack(spacing: 16) {
            ForEach(Array(model.whois.enumerated()), id: \.element.id) { index, step in
                WhoisStepView(step: step, startsExpanded: index == model.whois.count - 1)
            }
        }
    }
}

extension RDAPEvent.Action {
    var label: LocalizedStringResource {
        switch self {
        case .registration: "Registered"
        case .lastChanged: "Last changed"
        case .expiration: "Expires"
        }
    }
}

/// The raw text of one Whois server, folded. Whois has no fixed format, so
/// nothing is pulled out of it.
private struct WhoisStepView: View {
    let step: WhoisStep
    @State var startsExpanded: Bool

    init(step: WhoisStep, startsExpanded: Bool) {
        self.step = step
        _startsExpanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InfoCard {
                DisclosureGroup(isExpanded: $startsExpanded) {
                    Text(verbatim: step.text.isEmpty ? "–" : step.text)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } label: {
                    Text(verbatim: step.server).font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
        }
        .preference(
            key: SectionRecordsKey.self,
            value: [SectionRecord(title: step.server, rows: [RowRecord(label: "", value: step.text, sensitive: false, preformatted: true)])])
    }
}

// MARK: Ports

struct PortsView: View {
    @Bindable var model: PortsModel
    let history: ToolHistory

    var body: some View {
        VStack(spacing: 16) {
            ToolField(title: "Host or IP address", text: $model.input) { model.start() }
                .onChange(of: model.input) { model.classify() }
            RecentChips(items: history.recent(.ports)) { model.input = $0 }
            InfoCard {
                Toggle("Common ports (\(PortScanner.commonPorts.count))", isOn: $model.useCommonPorts)
                    .disabled(model.portsAreLocked)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                if !model.useCommonPorts && !model.portsAreLocked {
                    TextField("22,80,443 or 8000-8100", text: $model.portsText)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                }
            }
            if model.targetIsForeign == true {
                warning
            } else {
                ToolNote(Text("Tries to open a connection to each port. Nothing is sent."))
            }
            if let failure = model.failure { ErrorLine(failure: failure) }
            if let progress = model.progress { results(progress) }
        }
    }

    private var warning: some View {
        InfoCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Only scan devices that belong to you or that you have permission to scan. Outside your own network only the common ports are scanned.")
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func results(_ progress: (done: Int, total: Int)) -> some View {
        VStack(spacing: 16) {
            InfoSection(title: "Result") {
                if let address = model.address {
                    DataRow(label: "Address", value: address.text, monospaced: true, sensitive: true)
                }
                DataRow(
                    label: "Ports",
                    value: String(localized: "\(model.open.count) open · \(model.closedCount) closed · \(model.noResponseCount) no answer"))
                if model.isRunning {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            if !model.open.isEmpty {
                InfoSection(title: "Open ports") {
                    ForEach(model.open) { port in
                        DataRow(label: LocalizedStringResource(stringLiteral: "\(port.port)"), value: detail(port))
                    }
                }
            }
        }
    }

    private func detail(_ port: OpenPort) -> String {
        [PortNames.name(for: port.port).map { String(localized: "usually \($0)") }, port.milliseconds.map(milliseconds)]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: TLS

struct TLSView: View {
    @Bindable var model: TLSModel
    let history: ToolHistory

    var body: some View {
        VStack(spacing: 16) {
            ToolField(title: "Host or host:port", text: $model.input) { model.start() }
            RecentChips(items: history.recent(.tls)) { model.input = $0 }
            ToolNote(Text("Only the handshake happens. No data is sent."))
            if let failure = model.failure { ErrorLine(failure: failure) }
            if let report = model.report {
                InfoSection(title: "Connection") {
                    if let address = report.remoteAddress {
                        DataRow(label: "Address", value: address, monospaced: true, sensitive: true)
                    }
                    if let version = report.protocolVersion { DataRow(label: "Protocol", value: version) }
                    if let suite = report.cipherSuite { DataRow(label: "Cipher suite", value: suite, monospaced: true, stacked: true) }
                    switch report.trust {
                    case .trusted:
                        StatusRow(label: "Trust", text: String(localized: "Trusted by the system"))
                    case .untrusted(let reason):
                        StatusRow(label: "Trust", text: reason.isEmpty ? String(localized: "Not trusted") : reason, tone: .critical)
                    }
                }
                ForEach(Array(report.chain.enumerated()), id: \.offset) { index, certificate in
                    certificateSection(certificate, index: index, count: report.chain.count)
                }
            }
        }
    }

    private func certificateSection(_ certificate: CertificateInfo, index: Int, count: Int) -> some View {
        let title: LocalizedStringResource =
            index == 0 ? "Server certificate" : (index == count - 1 ? "Top of the chain" : "Intermediate certificate")
        let days = certificate.daysUntilExpiry()
        return InfoSection(title: title) {
            DataRow(label: "Name", value: certificate.subjectName ?? certificate.subjectOrganization ?? "–")
            if certificate.isSelfIssued == false, let issuer = certificate.issuerName ?? certificate.issuerOrganization {
                DataRow(label: "Issuer", value: issuer)
            }
            DataRow(label: "Valid from", value: certificate.notBefore.formatted(dateStyle))
            DataRow(label: "Valid until", value: certificate.notAfter.formatted(dateStyle))
            StatusRow(
                label: "Expires in",
                text: days < 0
                    ? String(localized: "Expired \(-days) days ago")
                    : String(localized: "\(days) days"),
                tone: days < 0 ? .critical : (days < 30 ? .warning : .good))
            if index == 0, !certificate.alternativeNames.isEmpty {
                DataRow(label: "Alternative names", value: certificate.alternativeNames.joined(separator: "\n"), monospaced: true)
            }
            DataRow(label: "Serial number", value: certificate.serialNumber, monospaced: true, stacked: true)
        }
    }
}

// MARK: HTTP timing

struct HTTPView: View {
    @Bindable var model: HTTPModel
    let history: ToolHistory

    var body: some View {
        VStack(spacing: 16) {
            ToolField(title: "Web address", text: $model.input) { model.start() }
            RecentChips(items: history.recent(.http)) { model.input = $0 }
            ToolNote(Text("Loads the page once, with no cache, and reads only the headers."))
            if let failure = model.failure { ErrorLine(failure: failure) }
            if model.steps.count > 1, let last = model.steps.last {
                InfoSection(title: "Redirects") {
                    DataRow(label: "Redirects", value: String(model.steps.count - 1))
                    DataRow(label: "Final address", value: last.url, monospaced: true, stacked: true)
                }
            }
            ForEach(model.steps) { step in
                InfoSection(title: model.steps.count > 1 ? "Request \(step.id + 1)" : "Result") {
                    DataRow(label: "Address", value: step.url, monospaced: true, stacked: true)
                    if let status = step.statusCode { DataRow(label: "Status", value: String(status)) }
                    if let location = step.location {
                        DataRow(label: "Redirects to", value: location, monospaced: true, stacked: true)
                    }
                    if let networkProtocol = step.networkProtocol { DataRow(label: "Protocol", value: networkProtocol) }
                    if let address = step.remoteAddress {
                        DataRow(
                            label: "Remote", value: step.remotePort.map { "\(address):\($0)" } ?? address,
                            monospaced: true, sensitive: true)
                    }
                    if let value = step.dnsMilliseconds { DataRow(label: "DNS lookup", value: milliseconds(value)) }
                    if let value = step.tcpMilliseconds { DataRow(label: "TCP connection", value: milliseconds(value)) }
                    if let value = step.tlsMilliseconds { DataRow(label: "TLS handshake", value: milliseconds(value)) }
                    if let value = step.waitMilliseconds { DataRow(label: "Time to first byte", value: milliseconds(value)) }
                    if let value = step.totalMilliseconds { DataRow(label: "Total until first byte", value: milliseconds(value)) }
                }
            }
            if let last = model.steps.last, !last.headers.isEmpty {
                InfoSection(title: "Response headers") {
                    ForEach(last.headers) { header in
                        DataRow(
                            label: LocalizedStringResource(stringLiteral: header.name), value: header.value,
                            monospaced: true, stacked: true)
                    }
                }
            }
        }
    }
}

// MARK: Subnet calculator

struct SubnetView: View {
    @Binding var input: String

    var body: some View {
        VStack(spacing: 16) {
            ToolField(title: "192.0.2.42/24", text: $input, keyboard: .numbersAndPunctuation, monospaced: true)
            ToolNote(Text("Runs on your device. Nothing is sent."))
            if !input.trimmingCharacters(in: .whitespaces).isEmpty {
                switch Result(catching: { try SubnetInfo(input) }) {
                case .success(let info): result(info)
                case .failure(let error): ErrorLine(failure: .input((error as? InputError) ?? .invalidSubnet))
                }
            }
        }
    }

    private func result(_ info: SubnetInfo) -> some View {
        InfoSection(title: "Network") {
            DataRow(label: "Network address", value: info.network, monospaced: true, sensitive: true)
            DataRow(label: "Subnet mask", value: info.mask, monospaced: true, sensitive: true)
            DataRow(label: "Prefix length", value: "/\(info.prefix)")
            DataRow(label: "Wildcard", value: info.wildcard, monospaced: true, sensitive: true)
            if let broadcast = info.broadcast {
                DataRow(label: "Broadcast", value: broadcast, monospaced: true, sensitive: true)
            }
            DataRow(label: "First host", value: info.firstHost, monospaced: true, sensitive: true)
            DataRow(label: "Last host", value: info.lastHost, monospaced: true, sensitive: true)
            DataRow(label: "Hosts", value: info.hostCount.formatted())
        }
    }
}

// MARK: OUI lookup

struct OUIView: View {
    @Environment(SnapshotStore.self) private var store
    @Binding var input: String

    var body: some View {
        VStack(spacing: 16) {
            ToolField(title: "MAC address or first three bytes", text: $input, keyboard: .asciiCapable, monospaced: true)
            ToolNote(Text("Looks the vendor up in the IEEE list on your device."))
            if !input.trimmingCharacters(in: .whitespaces).isEmpty {
                if store.oui.count == 0 {
                    InfoCard { LoadingRow(label: "Loading the vendor list") }
                } else {
                    switch Result(catching: { try store.oui.lookup(input) }) {
                    case .success(let result): row(result)
                    case .failure(let error): ErrorLine(failure: .input((error as? InputError) ?? .invalidMAC))
                    }
                }
            }
        }
    }

    private func row(_ result: OUIResult) -> some View {
        InfoSection(title: "Vendor") {
            switch result {
            case .vendor(let name): DataRow(label: "Vendor", value: name)
            case .locallyAdministered:
                DataRow(label: "Address type", value: String(localized: "Locally administered address"), stacked: true)
            case .notFound: DataRow(label: "Vendor", value: String(localized: "No entry in the IEEE list"))
            }
        }
    }
}
