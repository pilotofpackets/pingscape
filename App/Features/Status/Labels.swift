import NetKit

extension WiFiSecurity {
    /// `nil` when iOS does not say, so the row is left out.
    var label: String? {
        switch self {
        case .open: String(localized: "Open")
        case .wep: "WEP"
        case .personal: "WPA2/WPA3 Personal"
        case .enterprise: "WPA2/WPA3 Enterprise"
        case .unknown: nil
        }
    }
}

extension InterfaceKind {
    /// What the interface is used for, only where its name says so for sure.
    /// `awdl0`, `llw0` and other names get no label rather than a guess.
    var label: String? {
        switch self {
        case .loopback: String(localized: "Loopback")
        case .wifi: String(localized: "Wi-Fi")
        case .ethernet: String(localized: "Ethernet")
        case .hotspot: String(localized: "Personal Hotspot")
        case .cellular: String(localized: "Cellular")
        case .ipsec, .tunnel: String(localized: "Tunnel")
        case .other: nil
        }
    }
}
