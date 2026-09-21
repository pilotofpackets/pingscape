import Darwin

/// The `IFF_*` flags of a network interface, as `getifaddrs` reports them.
public struct InterfaceFlags: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let up = InterfaceFlags(rawValue: UInt32(IFF_UP))
    public static let broadcast = InterfaceFlags(rawValue: UInt32(IFF_BROADCAST))
    public static let loopback = InterfaceFlags(rawValue: UInt32(IFF_LOOPBACK))
    public static let pointToPoint = InterfaceFlags(rawValue: UInt32(IFF_POINTOPOINT))
    public static let running = InterfaceFlags(rawValue: UInt32(IFF_RUNNING))
    public static let noARP = InterfaceFlags(rawValue: UInt32(IFF_NOARP))
    public static let promiscuous = InterfaceFlags(rawValue: UInt32(IFF_PROMISC))
    public static let allMulticast = InterfaceFlags(rawValue: UInt32(IFF_ALLMULTI))
    public static let simplex = InterfaceFlags(rawValue: UInt32(IFF_SIMPLEX))
    public static let multicast = InterfaceFlags(rawValue: UInt32(IFF_MULTICAST))

    private static let named: [(InterfaceFlags, String)] = [
        (.up, "UP"), (.broadcast, "BROADCAST"), (.loopback, "LOOPBACK"),
        (.pointToPoint, "POINTOPOINT"), (.running, "RUNNING"), (.noARP, "NOARP"),
        (.promiscuous, "PROMISC"), (.allMulticast, "ALLMULTI"), (.simplex, "SIMPLEX"),
        (.multicast, "MULTICAST"),
    ]

    /// The technical flag names, such as `UP` and `RUNNING`. Not localized.
    public var names: [String] {
        Self.named.filter { contains($0.0) }.map(\.1)
    }
}
