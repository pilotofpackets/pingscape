/// What a network interface is used for, guessed from its name.
///
/// The classification only exists to find Wi-Fi, cellular and tunnels. It is
/// never shown as a claim about a protocol.
public enum InterfaceKind: String, Sendable, Codable, CaseIterable {
    case loopback
    case wifi
    case ethernet
    /// Personal Hotspot (`ap1`, `bridge100`).
    case hotspot
    case cellular
    /// `ipsecN` is either a VPN or the carrier tunnel for Wi-Fi Calling and
    /// VoLTE. Only the system's scoped service list tells them apart.
    case ipsec
    /// `utunN` (VPN apps, system tunnels) and `pppN`.
    case tunnel
    case other

    public init(interfaceName name: String) {
        if name.hasPrefix("lo") {
            self = .loopback
        } else if name == "en0" {
            // On iPhone and iPad the Wi-Fi interface is always en0.
            self = .wifi
        } else if name.hasPrefix("en") {
            self = .ethernet
        } else if name.hasPrefix("ap") || name.hasPrefix("bridge") {
            self = .hotspot
        } else if name.hasPrefix("pdp_ip") {
            self = .cellular
        } else if name.hasPrefix("ipsec") {
            self = .ipsec
        } else if name.hasPrefix("utun") || name.hasPrefix("ppp") {
            self = .tunnel
        } else {
            self = .other
        }
    }
}
