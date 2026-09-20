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
    public let mtu: Int?
    public let addresses: [InterfaceAddress]
    /// Bytes since boot. The system keeps 32-bit counters here, so they wrap
    /// after 4 GiB. 64-bit counters are a separate step.
    public let receivedBytes: UInt64?
    public let sentBytes: UInt64?

    public init(
        name: String,
        kind: InterfaceKind? = nil,
        isUp: Bool = true,
        mtu: Int? = nil,
        addresses: [InterfaceAddress] = [],
        receivedBytes: UInt64? = nil,
        sentBytes: UInt64? = nil
    ) {
        self.name = name
        self.kind = kind ?? InterfaceKind(interfaceName: name)
        self.isUp = isUp
        self.mtu = mtu
        self.addresses = addresses
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }

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
