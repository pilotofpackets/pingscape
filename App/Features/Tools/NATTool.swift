import NetKit
import Observation
import SwiftUI

// MARK: Model

/// Asks STUN servers which public address and port a UDP socket of this
/// device gets, and shows what follows from it without guessing a NAT type.
@MainActor
@Observable
final class NATModel: ToolControl {
    var ipv6 = false
    /// An own STUN server, `host` or `host:port`. Optional.
    var customServer = ""
    private(set) var isRunning = false
    private(set) var failure: ToolFailure?
    private(set) var report: STUNReport?
    private var task: Task<Void, Never>?

    var inputText: String { customServer }
    var canStart: Bool { true }

    func start() {
        stop()
        failure = nil
        report = nil
        var servers = STUNServer.defaults
        let text = customServer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            do {
                let (host, port) = try ToolInput.hostAndPort(text, defaultPort: 3478)
                servers.append(STUNServer(host: host, port: port ?? 3478))
            } catch let error as InputError {
                failure = .input(error)
                return
            } catch { return }
        }
        let ipv6 = ipv6
        isRunning = true
        task = Task {
            do {
                report = try await STUNTool.run(servers: servers, ipv6: ipv6)
            } catch is CancellationError {
                return
            } catch let error as ToolError {
                failure = .tool(error)
            } catch {
                failure = .tool(.unreadable)
            }
            if !Task.isCancelled { isRunning = false }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    static func demo() -> NATModel {
        let model = NATModel()
        func mapping(_ server: STUNServer, _ at: String, _ port: UInt16, _ ms: Double) -> STUNMapping {
            STUNMapping(
                server: server, serverAddress: at, publicAddress: "203.0.113.45", publicPort: port, milliseconds: ms,
                error: nil)
        }
        let servers = STUNServer.defaults
        model.report = STUNReport(
            localAddress: "192.168.178.42", localPort: 57833,
            mappings: [
                mapping(servers[0], "162.159.207.0", 33943, 15.2),
                mapping(servers[1], "74.125.250.129", 33943, 20.4),
                mapping(servers[2], "74.125.204.127", 33943, 21.0),
            ])
        return model
    }
}

// MARK: View

struct NATView: View {
    @Bindable var model: NATModel
    let history: ToolHistory
    @Environment(PrivacyMask.self) private var mask

    var body: some View {
        VStack(spacing: 16) {
            Picker("Address family", selection: $model.ipv6) {
                Text("IPv4").tag(false)
                Text("IPv6").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(model.isRunning)
            ToolField(title: "Own STUN server (optional)", text: $model.customServer) { model.start() }
            RecentChips(items: history.recent(.nat)) { model.customServer = $0 }
            ToolNote(Text("Sends a STUN request from one UDP port to Cloudflare and Google, which answer with the address and port they saw."))
            if let failure = model.failure { ErrorLine(failure: failure) }
            if let report = model.report { result(report) }
        }
    }

    private func result(_ report: STUNReport) -> some View {
        VStack(spacing: 16) {
            InfoSection(title: "Mapping") {
                if let address = report.localAddress, let port = report.localPort {
                    DataRow(
                        label: "This device", value: endpoint(address, port), monospaced: true, sensitive: true,
                        stacked: true)
                }
                if let seen = report.mappings.first(where: { $0.publicAddress != nil }),
                    let address = seen.publicAddress, let port = seen.publicPort
                {
                    DataRow(
                        label: "Seen from outside", value: endpoint(address, port), monospaced: true, sensitive: true,
                        stacked: true)
                }
                if let translated = report.isTranslated {
                    DataRow(
                        label: "Address translation",
                        value: translated ? String(localized: "Yes") : String(localized: "No"))
                }
                if let keeps = report.keepsPort {
                    DataRow(
                        label: "Port",
                        value: keeps ? String(localized: "Kept") : String(localized: "Changed"))
                }
                if let same = report.sameMappingForAllServers {
                    DataRow(
                        label: "Per destination",
                        value: same
                            ? String(localized: "Same for all servers") : String(localized: "Differs per server"))
                }
            }
            InfoSection(title: "Servers") {
                ForEach(report.mappings) { mapping in
                    DataRow(
                        label: LocalizedStringResource(stringLiteral: mapping.server.text),
                        value: text(mapping), monospaced: mapping.error == nil, stacked: true)
                }
            }
        }
    }

    private func endpoint(_ address: String, _ port: UInt16) -> String {
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }

    /// The public address as the server saw it, masked like any address.
    private func text(_ mapping: STUNMapping) -> String {
        if let address = mapping.publicAddress, let port = mapping.publicPort {
            let shown = mask.shown(address)
            let base = shown == address ? endpoint(address, port) : shown
            return [base, mapping.milliseconds.map(milliseconds)].compactMap { $0 }.joined(separator: " · ")
        }
        return mapping.error?.text ?? String(localized: "No reply")
    }
}
