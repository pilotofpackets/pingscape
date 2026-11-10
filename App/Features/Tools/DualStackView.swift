import NetKit
import Observation
import SwiftUI

// MARK: Model

/// Connects to a host over IPv4 and IPv6 and the way the system would, to
/// see which family is faster and which one the system picks.
@MainActor
@Observable
final class DualStackModel: ToolControl {
    var input = ""
    private(set) var isRunning = false
    private(set) var failure: ToolFailure?
    private(set) var report: DualStackReport?
    private(set) var port: UInt16 = 443
    private var task: Task<Void, Never>?

    var inputText: String { input }
    var canStart: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func start() {
        stop()
        failure = nil
        report = nil
        let host: String
        let port: UInt16
        do {
            let parsed = try ToolInput.hostAndPort(input, defaultPort: 443)
            host = parsed.host
            port = parsed.port ?? 443
        } catch let error as InputError {
            failure = .input(error)
            return
        } catch { return }
        self.port = port
        isRunning = true
        task = Task {
            do {
                report = try await DualStackTool.run(host: host, port: port)
            } catch is CancellationError {
                return
            } catch let error as ToolError {
                failure = .tool(error)
            } catch let error as InputError {
                failure = .input(error)
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

    static func demo() -> DualStackModel {
        let model = DualStackModel()
        model.input = "www.example.com"
        model.report = DualStackReport(
            ipv4: DualStackFamily(address: "192.0.2.80", medianMilliseconds: 18.2, attempts: [18.2, 19.0, 17.6], error: nil),
            ipv6: DualStackFamily(address: "2001:db8::80", medianMilliseconds: 14.1, attempts: [14.1, 13.8, 15.0], error: nil),
            systemAddress: "2001:db8::80", systemUsedIPv6: true, systemMilliseconds: 15.3)
        return model
    }
}

// MARK: View

struct DualStackView: View {
    @Bindable var model: DualStackModel
    let history: ToolHistory

    var body: some View {
        VStack(spacing: 16) {
            ToolField(title: "Host (optionally with :port)", text: $model.input) { model.start() }
            RecentChips(items: history.recent(.dualstack)) { model.input = $0 }
            ToolNote(Text("Opens TCP connections over IPv4 and IPv6 side by side, three times, then one the way the system picks itself (Happy Eyeballs). No data is sent."))
            if let failure = model.failure { ErrorLine(failure: failure) }
            if let report = model.report { result(report) }
        }
    }

    private func result(_ report: DualStackReport) -> some View {
        VStack(spacing: 16) {
            InfoSection(title: "Result") {
                if let faster = report.faster {
                    DataRow(
                        label: "Faster",
                        value: faster.ipv6
                            ? String(localized: "IPv6, by \(milliseconds(faster.byMilliseconds))")
                            : String(localized: "IPv4, by \(milliseconds(faster.byMilliseconds))"))
                }
                if let ipv6 = report.systemUsedIPv6 {
                    DataRow(label: "The system connected over", value: ipv6 ? "IPv6" : "IPv4")
                }
                if let address = report.systemAddress {
                    DataRow(label: "Address", value: address, monospaced: true, sensitive: true, stacked: address.contains(":"))
                }
                if let time = report.systemMilliseconds {
                    DataRow(label: "Time", value: milliseconds(time))
                }
                if report.systemUsedIPv6 == nil {
                    StatusRow(label: "The system connected over", text: String(localized: "No connection"), tone: .critical)
                }
            }
            family("IPv4", report.ipv4, missing: String(localized: "The system gave no IPv4 address"))
            family("IPv6", report.ipv6, missing: String(localized: "The system gave no IPv6 address"))
        }
    }

    private func family(_ title: String, _ family: DualStackFamily, missing: String) -> some View {
        InfoSection(title: LocalizedStringResource(stringLiteral: title)) {
            if let address = family.address {
                DataRow(label: "Address", value: address, monospaced: true, sensitive: true, stacked: address.contains(":"))
                if let median = family.medianMilliseconds {
                    DataRow(label: "TCP handshake (median)", value: milliseconds(median))
                    DataRow(
                        label: "Attempts",
                        value: family.attempts.map { $0.map(milliseconds) ?? "–" }.joined(separator: " · "))
                } else if let error = family.error {
                    StatusRow(label: "Result", text: error.text, tone: .critical)
                }
            } else {
                DataRow(label: "Result", value: missing)
            }
        }
    }
}
