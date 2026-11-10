import NetKit
import Observation
import SwiftUI

// MARK: Model

/// One time server's answer, or why there is none.
struct NTPRow: Identifiable {
    let host: String
    let result: Result<NTPResult, ToolFailure>

    var id: String { host }
}

/// Asks several time servers at once how far this device's clock is off.
@MainActor
@Observable
final class NTPModel: ToolControl {
    /// An own time server, in addition to the default ones. Optional.
    var customServer = ""
    private(set) var isRunning = false
    private(set) var failure: ToolFailure?
    private(set) var rows: [NTPRow] = []
    private var task: Task<Void, Never>?

    var inputText: String { customServer }
    var canStart: Bool { true }

    func start() {
        stop()
        failure = nil
        rows = []
        var hosts = NTPClient.defaultServers
        let text = customServer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            do {
                hosts.append(try ToolInput.host(text))
            } catch let error as InputError {
                failure = .input(error)
                return
            } catch { return }
        }
        isRunning = true
        task = Task {
            let answers = await withTaskGroup(of: NTPRow.self) { group in
                for host in hosts {
                    group.addTask {
                        do {
                            return NTPRow(host: host, result: .success(try await NTPClient.query(host: host)))
                        } catch let error as ToolError {
                            return NTPRow(host: host, result: .failure(.tool(error)))
                        } catch {
                            return NTPRow(host: host, result: .failure(.tool(.unreadable)))
                        }
                    }
                }
                var rows: [NTPRow] = []
                for await row in group { rows.append(row) }
                return rows
            }
            guard !Task.isCancelled else { return }
            rows = hosts.compactMap { host in answers.first { $0.host == host } }
            isRunning = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    static func demo() -> NTPModel {
        let model = NTPModel()
        let now = Date()
        model.rows = [
            NTPRow(host: "time.apple.com", result: .success(NTPResult(
                offsetMilliseconds: 1.4, delayMilliseconds: 15.2, stratum: 1, reference: "GPSs", serverTime: now,
                leapIndicator: 0))),
            NTPRow(host: "time.cloudflare.com", result: .success(NTPResult(
                offsetMilliseconds: 0.9, delayMilliseconds: 14.8, stratum: 3, reference: "10.125.9.225",
                serverTime: now, leapIndicator: 0))),
            NTPRow(host: "pool.ntp.org", result: .success(NTPResult(
                offsetMilliseconds: -6.8, delayMilliseconds: 18.3, stratum: 2, reference: "192.0.2.10", serverTime: now,
                leapIndicator: 0))),
        ]
        return model
    }
}

// MARK: View

struct NTPView: View {
    @Bindable var model: NTPModel
    let history: ToolHistory

    private static let timeStyle = Date.FormatStyle(date: .omitted, time: .standard)
        .secondFraction(.fractional(3))

    var body: some View {
        VStack(spacing: 16) {
            ToolField(title: "Own time server (optional)", text: $model.customServer) { model.start() }
            RecentChips(items: history.recent(.ntp)) { model.customServer = $0 }
            ToolNote(Text("Asks time.apple.com, time.cloudflare.com and pool.ntp.org at once (SNTP, UDP port 123)."))
            if let failure = model.failure { ErrorLine(failure: failure) }
            ForEach(model.rows) { row in
                InfoSection(title: LocalizedStringResource(stringLiteral: row.host)) {
                    switch row.result {
                    case .success(let result): rows(result)
                    case .failure(let failure): StatusRow(label: "Result", text: failure.text, tone: .critical)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ result: NTPResult) -> some View {
        if result.stratum == 0 {
            StatusRow(
                label: "Result",
                text: String(localized: "The server refused to answer (\(result.reference ?? "KoD"))"), tone: .warning)
        } else {
            DataRow(label: "This device's clock", value: clockText(result.offsetMilliseconds))
            DataRow(label: "Round trip", value: milliseconds(result.delayMilliseconds))
            DataRow(label: "Stratum", value: String(result.stratum))
            if let reference = result.reference {
                DataRow(label: "Reference", value: reference, monospaced: true)
            }
            DataRow(label: "Server time", value: result.serverTime.formatted(Self.timeStyle))
            switch result.leapIndicator {
            case 1, 2: DataRow(label: "Leap second", value: String(localized: "Announced for the end of the day"))
            case 3: StatusRow(label: "Server clock", text: String(localized: "Not synchronized"), tone: .warning)
            default: EmptyView()
            }
        }
    }

    /// The offset from the device's side: a server ahead means the device is behind.
    private func clockText(_ offset: Double) -> String {
        let amount = milliseconds(abs(offset))
        return offset >= 0 ? String(localized: "\(amount) behind") : String(localized: "\(amount) ahead")
    }
}
