/// How much traffic a VPN tunnel carries.
public enum TunnelScope: Sendable, Hashable {
    /// A default route (or the two half routes) leads through the tunnel.
    case full
    /// A tunnel exists, but the internet traffic goes out directly.
    case partial
}

// The rules below come from the reference app's field experience. Each one
// exists because a simpler rule gave a wrong answer on a real iPhone.
extension NetworkSnapshot {
    private static let primaryOrder: [InterfaceKind] = [.wifi, .ethernet, .cellular]

    /// The interface whose address counts as "the local address".
    ///
    /// Wi-Fi first, then a cable adapter, then cellular. Tunnels and the
    /// personal hotspot are never candidates: neither a VPN nor the carrier's
    /// IPsec tunnel is the local connection, and a hotspot interface holds the
    /// address the device hands out to others.
    public var primaryInterface: NetworkInterface? {
        for kind in Self.primaryOrder {
            if let match = usableInterface(of: kind, mustBeUp: true) { return match }
        }
        // Unknown interface names, for example in a simulator: any real
        // address, but still nothing that is a tunnel or a hotspot.
        return interfaces.first { $0.kind == .other && $0.isUp && $0.hasUsableAddress }
    }

    public var primaryIPv4: InterfaceAddress? { primaryInterface?.ipv4Addresses.first }
    public var primaryIPv6: InterfaceAddress? { primaryInterface?.ipv6Addresses.first }

    public func interface(of kind: InterfaceKind) -> NetworkInterface? {
        usableInterface(of: kind, mustBeUp: false)
    }

    /// The first interface of a kind with a usable address. An iPhone has
    /// several `pdp_ip` interfaces (IMS, second SIM), so for cellular the one
    /// the system names for cellular comes first.
    private func usableInterface(of kind: InterfaceKind, mustBeUp: Bool) -> NetworkInterface? {
        let usable = interfaces.filter { $0.kind == kind && (!mustBeUp || $0.isUp) && $0.hasUsableAddress }
        if kind == .cellular, let name = path?.cellularInterface, let named = usable.first(where: { $0.name == name }) {
            return named
        }
        return usable.first
    }

    /// Whether an interface is a VPN tunnel the user (or an app) set up.
    ///
    /// A tunnel (`utun`, `ppp`) counts if the system lists it as a network
    /// service, or if the internet traffic goes through it (an active default
    /// route). `ipsec` counts only if the system lists it as a service.
    /// Otherwise it is the carrier tunnel for Wi-Fi Calling and VoLTE.
    ///
    /// A usable address is not enough. iOS 27 keeps a system `utun` with a
    /// unique-local IPv6 address (MTU 16000) that is no VPN. It is in neither
    /// list, and its default route is not active. Seen on an iPhone 15 without a
    /// VPN and with WireGuard on, see the two `dump-ios27-*` fixtures.
    public func isVPN(_ interface: NetworkInterface) -> Bool {
        guard interface.isUp, interface.hasUsableAddress else { return false }
        switch interface.kind {
        case .tunnel: return vpnServiceInterfaces.contains(interface.name) || carriesTraffic(interface)
        case .ipsec: return vpnServiceInterfaces.contains(interface.name)
        default: return false
        }
    }

    /// All active tunnels. WireGuard and an IPsec VPN can exist side by side.
    public var vpnInterfaces: [NetworkInterface] { interfaces.filter(isVPN) }
    public var isVPNActive: Bool { !vpnInterfaces.isEmpty }

    /// The gateway of an interface from its default route, even if that route
    /// is not the active one (the Wi-Fi gateway while a VPN takes over).
    public func gateway(of interface: NetworkInterface, ipv6: Bool = false) -> String? {
        var fallback: String?
        for route in defaultRoutes
        where route.interfaceName == interface.name && route.isIPv6 == ipv6 {
            guard let gateway = route.gateway else { continue }
            if route.isActive { return gateway }
            fallback = fallback ?? gateway
        }
        return fallback
    }

    /// The default gateway of the local connection, not the one of a VPN that
    /// installed its own route.
    public var localGateway4: String? { localGateway(ipv6: false) }
    public var localGateway6: String? { localGateway(ipv6: true) }

    /// Cellular has no local gateway: the "gateway" of a `pdp_ip` interface is
    /// the carrier end of a point-to-point link (often the device's own address).
    private func localGateway(ipv6: Bool) -> String? {
        guard !defaultRoutes.isEmpty, let primary = primaryInterface, primary.kind != .cellular else { return nil }
        return gateway(of: primary, ipv6: ipv6)
    }

    /// True if an active default route of this interface exists, so the
    /// traffic of that address family leaves through it.
    public func carriesTraffic(_ interface: NetworkInterface, ipv6: Bool? = nil) -> Bool {
        defaultRoutes.contains {
            $0.interfaceName == interface.name && $0.isActive && (ipv6 == nil || $0.isIPv6 == ipv6)
        }
    }

    /// Full if a VPN carries the internet traffic, partial if a VPN exists but
    /// traffic goes out directly, `nil` without a VPN.
    public var tunnelScope: TunnelScope? {
        guard isVPNActive else { return nil }
        return vpnInterfaces.contains { carriesTraffic($0) } ? .full : .partial
    }

    /// The network of the primary interface, used for the LAN sweep. Only Wi-Fi
    /// and cable have a local network, cellular does not.
    public var lanRange: IPv4Range? {
        guard let primary = primaryInterface, primary.kind != .cellular, let address = primary.ipv4Addresses.first
        else { return nil }
        let prefix = address.prefixLength ?? address.netmask.flatMap(IPv4.prefix(fromNetmask:)) ?? 24
        return IPv4Range(ip: address.ip, prefix: prefix)
    }
}
