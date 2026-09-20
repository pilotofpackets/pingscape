import Foundation

/// The reachability state the system reports (`NWPath`).
public struct PathSummary: Sendable, Hashable, Codable {
    public let isOnline: Bool
    public let supportsIPv4: Bool
    public let supportsIPv6: Bool
    public let supportsDNS: Bool
    /// Cellular or hotspot connections the system marks as costly.
    public let isExpensive: Bool
    /// Low Data Mode.
    public let isConstrained: Bool

    public init(
        isOnline: Bool,
        supportsIPv4: Bool = true,
        supportsIPv6: Bool = true,
        supportsDNS: Bool = true,
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) {
        self.isOnline = isOnline
        self.supportsIPv4 = supportsIPv4
        self.supportsIPv6 = supportsIPv6
        self.supportsDNS = supportsDNS
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }
}

/// Everything the app knows about the device's network at one moment.
///
/// A value type on purpose: collectors fill it, the UI reads it, and tests
/// build it from fixtures. All derived facts (primary interface, VPN, gateway)
/// live in `NetworkSnapshot+Derived.swift` as pure functions.
public struct NetworkSnapshot: Sendable {
    public var takenAt: Date
    public var path: PathSummary?
    public var interfaces: [NetworkInterface]
    public var defaultRoutes: [DefaultRoute]
    public var dnsServers: [String]
    public var proxy: ProxyInfo
    /// Tunnel interfaces the system lists as configured network services
    /// (the `__SCOPED__` section of the proxy settings).
    public var vpnServiceInterfaces: Set<String>
    public var wifi: Availability<WiFiInfo>
    public var cellularServices: [CellularService]
    /// Filled only on request, because it needs a request to the internet.
    public var publicIPv4: Availability<String>
    public var publicIPv6: Availability<String>

    public init(
        takenAt: Date = Date(),
        path: PathSummary? = nil,
        interfaces: [NetworkInterface] = [],
        defaultRoutes: [DefaultRoute] = [],
        dnsServers: [String] = [],
        proxy: ProxyInfo = ProxyInfo(),
        vpnServiceInterfaces: Set<String> = [],
        wifi: Availability<WiFiInfo> = .none,
        cellularServices: [CellularService] = [],
        publicIPv4: Availability<String> = .none,
        publicIPv6: Availability<String> = .none
    ) {
        self.takenAt = takenAt
        self.path = path
        self.interfaces = interfaces
        self.defaultRoutes = defaultRoutes
        self.dnsServers = dnsServers
        self.proxy = proxy
        self.vpnServiceInterfaces = vpnServiceInterfaces
        self.wifi = wifi
        self.cellularServices = cellularServices
        self.publicIPv4 = publicIPv4
        self.publicIPv6 = publicIPv6
    }
}
