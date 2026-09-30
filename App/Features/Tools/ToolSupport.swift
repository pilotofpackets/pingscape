import NetKit
import Observation
import SwiftUI

/// Why a tool run stopped: what was typed, or what the network did.
enum ToolFailure: Equatable {
    case input(InputError)
    case tool(ToolError)
    /// For a target in the local network: a refusal by the system means the
    /// Local Network permission is missing.
    case localNetworkDenied

    var text: String {
        switch self {
        case .input(let error): error.text
        case .tool(let error): error.text
        case .localNetworkDenied: String(localized: "Local network access is not allowed")
        }
    }

    /// The error of a run, aware of whether the target is in the local network.
    static func from(_ error: ToolError, target: ResolvedAddress?) -> ToolFailure {
        if error == .notPermitted, target?.isLocal == true { return .localNetworkDenied }
        return .tool(error)
    }
}

extension InputError {
    var text: String {
        switch self {
        case .empty: String(localized: "Enter a target first")
        case .invalidHost: String(localized: "This is not a valid host name or IP address")
        case .invalidPort: String(localized: "The port must be a number from 1 to 65535")
        case .invalidPortList: String(localized: "Ports look like 22,80,443 or 8000-8100")
        case .tooManyPorts: String(localized: "At most 5000 ports per run")
        case .invalidURL: String(localized: "This is not a valid web address")
        case .invalidSubnet: String(localized: "Use an address with a prefix, like 192.0.2.42/24")
        case .invalidMAC: String(localized: "Enter a MAC address or its first three bytes")
        }
    }
}

extension ToolError {
    var text: String {
        switch self {
        case .cannotResolve: String(localized: "Name could not be resolved")
        case .timeout: String(localized: "No answer within the time limit")
        case .refused: String(localized: "Connection refused")
        case .noRoute: String(localized: "No network route to the target")
        case .notPermitted: String(localized: "The system did not allow the request")
        case .noRegistry: String(localized: "No record found")
        case .unreadable: String(localized: "The answer could not be read")
        case .handshakeFailed: String(localized: "The TLS handshake failed")
        case .insecureConnection: String(localized: "Plain HTTP works only for local addresses. Use https://")
        case .failed(let message): message
        }
    }
}

/// What the start bar drives. Each tool's model conforms to it.
@MainActor
protocol ToolControl: AnyObject {
    /// The target field, for the list of recent targets.
    var inputText: String { get }
    var isRunning: Bool { get }
    var canStart: Bool { get }
    func start()
    func stop()
}

/// Targets used earlier in this session, per tool. Only in memory: nothing is
/// saved, so nothing has to be cleared.
@MainActor
@Observable
final class ToolHistory {
    private var entries: [ToolKind: [String]] = [:]

    func recent(_ tool: ToolKind) -> [String] { entries[tool] ?? [] }

    func remember(_ text: String, for tool: ToolKind) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = entries[tool] ?? []
        list.removeAll { $0 == trimmed }
        list.insert(trimmed, at: 0)
        entries[tool] = Array(list.prefix(5))
    }
}

// MARK: Components

/// The card with the text field of a tool.
struct ToolField: View {
    let title: LocalizedStringResource
    @Binding var text: String
    var keyboard: UIKeyboardType = .URL
    var monospaced = false
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            TextField(text: $text, prompt: Text(title)) { Text(title) }
                .keyboardType(keyboard)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A short line under a field: where the request goes.
struct ToolNote: View {
    let text: Text

    init(_ text: Text) { self.text = text }

    var body: some View {
        text
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }
}

/// A failure as a row, never as an alert.
struct ErrorLine: View {
    let failure: ToolFailure

    var body: some View {
        InfoCard {
            HStack(spacing: 8) {
                StatusDot(tone: .critical)
                Text(failure.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Recent targets of the tool, as chips.
struct RecentChips: View {
    let items: [String]
    let pick: (String) -> Void

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        Button {
                            pick(item)
                        } label: {
                            Text(verbatim: item)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
            .accessibilityLabel("Recent")
        }
    }
}

/// Copy and share (as text, image or JSON) of a result.
struct ResultActions: View {
    let text: String
    let baseName: String
    let sections: [SectionRecord]

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Pasteboard.copy(text)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .accessibilityLabel("Copy")
            ExportMenu(fileBaseName: baseName, header: [], sections: sections)
        }
        .font(.subheadline)
    }
}

/// The floating Start or Stop button.
struct StartBar: View {
    let control: any ToolControl
    let onStart: () -> Void

    var body: some View {
        Button {
            if control.isRunning {
                control.stop()
            } else {
                control.start()
                onStart()
            }
        } label: {
            Label(control.isRunning ? "Stop" : "Start", systemImage: control.isRunning ? "stop.fill" : "play.fill")
                .font(.headline)
                .padding(.horizontal, 32)
                .frame(minHeight: 50)
                .glassSurface(cornerRadius: 25)
        }
        .buttonStyle(.plain)
        .disabled(!control.isRunning && !control.canStart)
        .opacity(!control.isRunning && !control.canStart ? 0.5 : 1)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .light), trigger: control.isRunning)
    }
}

/// A time in milliseconds as text: "13 ms" or "0.4 ms".
func milliseconds(_ value: Double) -> String {
    if value >= 10 { return "\(Int(value.rounded())) ms" }
    return "\(value.formatted(.number.precision(.fractionLength(1)))) ms"
}
