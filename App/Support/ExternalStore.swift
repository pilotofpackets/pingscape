import Foundation
import NetKit
import Network
import Observation

/// The state of one value that is loaded on request.
enum LoadState<Value: Sendable>: Sendable {
    case notLoaded
    case loading
    case loaded(Value)
    /// The request failed. The row offers "Try again".
    case failed
    /// The request worked and there is no value (no IPv6, an unannounced
    /// address). The row is left out.
    case unavailable

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// The values of the "External" page: public address, its reverse DNS name and
/// the provider behind it. Loads only with the user's consent, on request, and
/// never more often than every 30 seconds.
@MainActor
@Observable
final class ExternalStore {
    private(set) var ipv4: LoadState<String> = .notLoaded
    private(set) var ipv6: LoadState<String> = .notLoaded
    private(set) var reverseName: LoadState<String> = .notLoaded
    private(set) var provider: LoadState<ProviderInfo> = .notLoaded
    private(set) var internetCheck: LoadState<InternetCheck> = .notLoaded
    /// The address as it looks from one specific interface (Wi-Fi or
    /// cellular), bypassing a full-tunnel VPN. Only asked for on a tap, and
    /// only meaningful while such a tunnel is active (see the Connection card).
    private(set) var boundIPv4: LoadState<String> = .notLoaded
    private(set) var boundIPv6: LoadState<String> = .notLoaded

    private let settings: AppSettings
    private let isDemo: Bool
    private var lastLoad: Date?
    private var providerCache: [String: (info: ProviderInfo?, date: Date)] = [:]
    private var loadTask: Task<Void, Never>?

    /// At least this long between two loads, unless the user asks.
    private static let minimumInterval: TimeInterval = 30
    /// How long a provider answer is reused for the same address.
    private static let providerLifetime: TimeInterval = 600

    init(settings: AppSettings, isDemo: Bool = DemoLaunch.isDemo) {
        self.settings = settings
        self.isDemo = isDemo
    }

    /// Whether the rows have anything to show or offer.
    var isEnabled: Bool { settings.externalLookups }

    /// Loads if the user agreed to external requests. A tap on "Load"
    /// (`userRequested`) is consent for that one load: it works while the
    /// setting is off, and it does not switch the setting on.
    func load(force: Bool = false, userRequested: Bool = false) {
        guard settings.externalLookups || userRequested else { return }
        if !force && !userRequested, let lastLoad, Date().timeIntervalSince(lastLoad) < Self.minimumInterval { return }
        guard loadTask == nil else { return }
        lastLoad = Date()
        loadTask = Task { [weak self] in
            await self?.run()
            self?.loadTask = nil
        }
    }

    /// Clears everything when the user turns external requests off.
    func reset() {
        loadTask?.cancel()
        loadTask = nil
        lastLoad = nil
        ipv4 = .notLoaded
        ipv6 = .notLoaded
        reverseName = .notLoaded
        provider = .notLoaded
        boundIPv4 = .notLoaded
        boundIPv6 = .notLoaded
    }

    /// Asks for the address as seen from one named interface, around a VPN
    /// that carries the default route. A tap on "Load" is its own consent,
    /// like the plain address (`userRequested`); otherwise it needs the
    /// setting to be on. There is no automatic reload: this is the secondary,
    /// less-used value, and a full-tunnel VPN rarely changes the underlying
    /// Wi-Fi or cellular connection while it runs.
    func loadBound(interfaceName: String, userRequested: Bool = false) {
        guard settings.externalLookups || userRequested else { return }
        if isDemo {
            boundIPv4 = .loaded("198.51.100.23")
            boundIPv6 = .unavailable
            return
        }
        boundIPv4 = .loading
        boundIPv6 = .loading
        Task { [weak self] in
            guard let self else { return }
            let interfaces = await PathCollector.availableInterfaces()
            guard let interface = interfaces.first(where: { $0.name == interfaceName }) else {
                boundIPv4 = .failed
                boundIPv6 = .unavailable
                return
            }
            async let fetched4 = boundFetch(.v4, over: interface)
            async let fetched6 = boundFetch(.v6, over: interface, quiet: true)
            (boundIPv4, boundIPv6) = await (fetched4, fetched6)
        }
    }

    private func boundFetch(_ version: PublicIPLookup.Version, over interface: NWInterface, quiet: Bool = false) async
        -> LoadState<String>
    {
        do {
            if let address = try await PublicIPLookup.fetch(version, over: interface) { return .loaded(address) }
            return quiet ? .unavailable : .failed
        } catch {
            return quiet ? .unavailable : .failed
        }
    }

    private func run() async {
        if isDemo {
            ipv4 = .loaded("203.0.113.57")
            ipv6 = .loaded("2001:db8:1::57")
            reverseName = .loaded("host.example.net")
            provider = .loaded(ProviderInfo(asNumber: "AS64500", organization: "Example Telecom", network: "203.0.113.0/24"))
            return
        }
        ipv4 = .loading
        ipv6 = .loading
        reverseName = .loading
        provider = .loading

        async let fetched4 = fetch(.v4)
        async let fetched6 = fetch(.v6, quiet: true)
        let (first, second) = await (fetched4, fetched6)
        ipv4 = first
        ipv6 = second
        guard !Task.isCancelled else { return }

        // The provider and the name belong to the address the internet sees.
        guard let address = first.value ?? second.value else {
            reverseName = .unavailable
            provider = first.isFailed ? .failed : .unavailable
            return
        }
        async let name = HostResolver.reverseName(of: address)
        async let info = providerInfo(for: address)
        let (resolved, providerResult) = await (name, info)
        reverseName = resolved.map { .loaded($0) } ?? .unavailable
        provider = providerResult
    }

    /// `quiet`: a failure means there is no such connection (no IPv6), not an error.
    private func fetch(_ version: PublicIPLookup.Version, quiet: Bool = false) async -> LoadState<String> {
        do {
            if let address = try await PublicIPLookup.fetch(version) { return .loaded(address) }
            return quiet ? .unavailable : .failed
        } catch {
            return quiet ? .unavailable : .failed
        }
    }

    private func providerInfo(for address: String) async -> LoadState<ProviderInfo> {
        if let cached = providerCache[address], Date().timeIntervalSince(cached.date) < Self.providerLifetime {
            return cached.info.map { .loaded($0) } ?? .unavailable
        }
        do {
            let info = try await RIPEstat.provider(for: address)
            providerCache[address] = (info, Date())
            return info.map { .loaded($0) } ?? .unavailable
        } catch {
            return .failed
        }
    }

    /// The captive portal probe, only on a tap.
    func checkInternet() {
        guard !internetCheck.isLoading else { return }
        internetCheck = .loading
        if isDemo {
            internetCheck = .loaded(.reachable)
            return
        }
        Task {
            internetCheck = .loaded(await InternetCheck.run())
        }
    }
}

extension LoadState where Value == String {
    fileprivate var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
