import Foundation

/// Why the system says the network is not reachable (`NWPath.unsatisfiedReason`).
public enum UnsatisfiedReason: String, Sendable, Hashable, Codable {
    case notAvailable
    case cellularDenied
    case wifiDenied
    case localNetworkDenied
    case vpnInactive
}

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
    /// The gateways the system lists for the path, as a cross-check for the routing table.
    public let gateways: [String]
    /// Only set while the path is not satisfied and the system names a reason.
    public let unsatisfiedReason: UnsatisfiedReason?

    public init(
        isOnline: Bool,
        supportsIPv4: Bool = true,
        supportsIPv6: Bool = true,
        supportsDNS: Bool = true,
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        gateways: [String] = [],
        unsatisfiedReason: UnsatisfiedReason? = nil
    ) {
        self.isOnline = isOnline
        self.supportsIPv4 = supportsIPv4
        self.supportsIPv6 = supportsIPv6
        self.supportsDNS = supportsDNS
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.gateways = gateways
        self.unsatisfiedReason = unsatisfiedReason
    }

    // Dumps written before `gateways` and `unsatisfiedReason` existed stay readable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOnline = try container.decode(Bool.self, forKey: .isOnline)
        supportsIPv4 = try container.decode(Bool.self, forKey: .supportsIPv4)
        supportsIPv6 = try container.decode(Bool.self, forKey: .supportsIPv6)
        supportsDNS = try container.decode(Bool.self, forKey: .supportsDNS)
        isExpensive = try container.decode(Bool.self, forKey: .isExpensive)
        isConstrained = try container.decode(Bool.self, forKey: .isConstrained)
        gateways = try container.decodeIfPresent([String].self, forKey: .gateways) ?? []
        unsatisfiedReason = try container.decodeIfPresent(UnsatisfiedReason.self, forKey: .unsatisfiedReason)
    }
}

/// Everything the app knows about the device's network at one moment.
///
/// A value type on purpose: collectors fill it, the UI reads it, and tests
/// build it from fixtures. All derived facts (primary interface, VPN, gateway)
/// live in `NetworkSnapshot+Derived.swift` as pure functions.
public struct NetworkSnapshot: Sendable, Codable {
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
