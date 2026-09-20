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
        for await _ in PathCollector.changes() {
            await refresh()
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        snapshot = await provider.snapshot()
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
