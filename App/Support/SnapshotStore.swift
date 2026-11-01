import CoreTelephony
import Foundation
import NetKit
import Observation

/// Holds the current snapshot and refreshes it when the network changes.
@MainActor
@Observable
final class SnapshotStore {
    private(set) var snapshot: NetworkSnapshot?
    private(set) var oui = OUIRegistry()
    private(set) var isRefreshing = false
    private var refreshAgain = false
    /// Changes seen while the app runs, newest first. Only in memory.
    private(set) var timeline = TimelineLog()
    /// Counts network path changes, so other parts can react to them.
    private(set) var pathChanges = 0
    private(set) var cellularAccess = CellularDataAccess.current

    private let provider: any NetworkSnapshotProviding
    let location = LocationPermission()

    init(provider: any NetworkSnapshotProviding) {
        self.provider = provider
        location.onChange = { [weak self] in
            Task { await self?.refresh() }
        }
    }

    /// Loads the vendor table, then refreshes on every network change.
    func run() async {
        async let registry = Self.loadRegistry()
        await refresh()
        oui = await registry
        // The system posts this when the radio technology changes (4G to 5G).
        let radio = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .CTServiceRadioAccessTechnologyDidChange)
            {
                await self?.refresh()
            }
        }
        defer { radio.cancel() }
        for await _ in PathCollector.changes() {
            await refresh()
            // After the refresh, so whoever reacts to it sees the new state.
            pathChanges += 1
        }
    }

    func refresh() async {
        // A request that comes in while one runs is not dropped but runs
        // right after it. Dropped, it left the overview stale: switching to
        // Airplane Mode with the app open, the radio notification came during
        // the path refresh, and 4G stayed on screen (found 2026-11-01).
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            let next = await provider.snapshot()
            timeline.record(from: snapshot, to: next)
            snapshot = next
            cellularAccess = CellularDataAccess.current
        } while refreshAgain
    }

    private nonisolated static func loadRegistry() async -> OUIRegistry {
        await Task.detached(priority: .utility) {
            guard let url = Bundle.main.url(forResource: "oui", withExtension: "txt"),
                let text = try? String(contentsOf: url, encoding: .utf8)
            else { return OUIRegistry() }
            return OUIRegistry(text: text)
        }.value
    }
}
