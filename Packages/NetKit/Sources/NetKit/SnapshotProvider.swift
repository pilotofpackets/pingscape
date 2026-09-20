import Foundation

/// Where snapshots come from: the device, or fixtures for demos and previews.
public protocol NetworkSnapshotProviding: Sendable {
    func snapshot() async -> NetworkSnapshot
}

/// Reads the real system state.
public struct LiveSnapshotProvider: NetworkSnapshotProviding {
    private let locationAuthorized: @Sendable () -> Bool

    /// `locationAuthorized` tells whether the location permission is granted.
    /// It decides between "not connected" and "permission needed" for Wi-Fi.
    public init(locationAuthorized: @escaping @Sendable () -> Bool = { false }) {
        self.locationAuthorized = locationAuthorized
    }

    public func snapshot() async -> NetworkSnapshot {
        async let path = PathCollector.current()
        let interfaces = InterfaceCollector.collect()
        let proxy = ProxyCollector.collect()

        var snapshot = NetworkSnapshot(
            interfaces: interfaces,
            defaultRoutes: RouteCollector.defaultRoutes(),
            dnsServers: DNSCollector.servers(),
            proxy: proxy.proxy,
            vpnServiceInterfaces: proxy.vpnServiceInterfaces)
        #if os(iOS)
        snapshot.wifi = await WiFiCollector.collect(
            interfaces: interfaces, locationAuthorized: locationAuthorized())
        snapshot.cellularServices = CellularCollector.services()
        #endif
        snapshot.path = await path
        return snapshot
    }
}

/// Serves fixtures. Launch the app with `-demo` to use it.
public struct DemoSnapshotProvider: NetworkSnapshotProviding {
    public init() {}

    public func snapshot() async -> NetworkSnapshot { DemoData.snapshot }
}
