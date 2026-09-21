public struct InterfaceAddress: Sendable, Hashable, Codable {
    public let ip: String
    public let isIPv6: Bool
    public let prefixLength: Int?
    public let netmask: String?

    public init(ip: String, isIPv6: Bool, prefixLength: Int? = nil, netmask: String? = nil) {
        self.ip = ip
        self.isIPv6 = isIPv6
        self.prefixLength = prefixLength
        self.netmask = netmask
    }

    /// Link-local and loopback addresses are of no interest for display.
    public var isUsable: Bool {
        if ip.isEmpty { return false }
        if ip.hasPrefix("fe80") || ip.hasPrefix("169.254") { return false }
        if ip == "127.0.0.1" || ip == "::1" { return false }
        return true
    }

    public var withPrefix: String {
        prefixLength.map { "\(ip)/\($0)" } ?? ip
    }
}

public struct NetworkInterface: Sendable, Hashable, Codable, Identifiable {
    public var id: String { name }

    public let name: String
    public let kind: InterfaceKind
    public let isUp: Bool
    public let flags: InterfaceFlags
    public let mtu: Int?
    public let addresses: [InterfaceAddress]
    /// Bytes and packets since boot, from the 64-bit counters. `nil` if the
    /// system did not deliver them.
    public let receivedBytes: UInt64?
    public let sentBytes: UInt64?
    public let receivedPackets: UInt64?
    public let sentPackets: UInt64?

    /// `flags` defaults to a plain up-and-running interface (or none if `isUp`
    /// is false), which is what tests and fixtures usually mean.
    public init(
        name: String,
        kind: InterfaceKind? = nil,
        isUp: Bool = true,
        flags: InterfaceFlags? = nil,
        mtu: Int? = nil,
        addresses: [InterfaceAddress] = [],
        receivedBytes: UInt64? = nil,
        sentBytes: UInt64? = nil,
        receivedPackets: UInt64? = nil,
        sentPackets: UInt64? = nil
    ) {
        self.name = name
        self.kind = kind ?? InterfaceKind(interfaceName: name)
        self.isUp = isUp
        self.flags = flags ?? (isUp ? [.up, .running] : [])
        self.mtu = mtu
        self.addresses = addresses
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.receivedPackets = receivedPackets
        self.sentPackets = sentPackets
    }

    /// Up and running: the interface has a link and carries traffic.
    public var isRunning: Bool { flags.contains([.up, .running]) }

    public var usableAddresses: [InterfaceAddress] { addresses.filter(\.isUsable) }
    public var ipv4Addresses: [InterfaceAddress] { usableAddresses.filter { !$0.isIPv6 } }
    public var ipv6Addresses: [InterfaceAddress] { usableAddresses.filter(\.isIPv6) }
    public var hasUsableAddress: Bool { !usableAddresses.isEmpty }
}

/// A default route (destination 0.0.0.0 or ::) of one interface.
public struct DefaultRoute: Sendable, Hashable, Codable {
    public let interfaceName: String
    public let gateway: String?
    public let isIPv6: Bool
    /// False for routes bound to one interface (`RTF_IFSCOPE`). Those only
    /// carry traffic that explicitly goes out through that interface, for
    /// example the Wi-Fi route while a VPN has taken over.
    public let isActive: Bool

    public init(interfaceName: String, gateway: String? = nil, isIPv6: Bool = false, isActive: Bool = true) {
        self.interfaceName = interfaceName
        self.gateway = gateway
        self.isIPv6 = isIPv6
        self.isActive = isActive
    }
}

public struct ProxyInfo: Sendable, Hashable, Codable {
    public let isEnabled: Bool
    public let host: String?
    public let port: Int?
    public let pacURL: String?

    public init(isEnabled: Bool = false, host: String? = nil, port: Int? = nil, pacURL: String? = nil) {
        self.isEnabled = isEnabled
        self.host = host
        self.port = port
        self.pacURL = pacURL
    }
}
