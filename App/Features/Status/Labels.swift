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

extension ConnectionKind {
    var label: String {
        switch self {
        case .wifi: String(localized: "Wi-Fi")
        case .cellular: String(localized: "Cellular")
        case .ethernet: String(localized: "Ethernet")
        case .other: String(localized: "Other")
        case .offline: String(localized: "Offline")
        }
    }
}

extension TimelineChange {
    /// The event as a line, and whether it holds a network identifier.
    var text: (value: String, sensitive: Bool) {
        switch self {
        case .connection(let from, let to):
            (String(localized: "Connection: \(from.label) → \(to.label)"), false)
        case .vpn(let isActive):
            (isActive ? String(localized: "VPN active") : String(localized: "VPN ended"), false)
        case .bssid(let from, let to):
            (String(localized: "Access point: \(from) → \(to)"), true)
        case .radio(let from, let to, let isDataService):
            (
                isDataService
                    ? String(localized: "Radio technology: \(from.label) → \(to.label)")
                    : String(localized: "Second SIM: \(from.label) → \(to.label)"), false
            )
        }
    }
}

extension UnsatisfiedReason {
    /// The reason in plain words. `notAvailable` says no more than "offline",
    /// so it adds nothing.
    var text: String? {
        switch self {
        case .notAvailable: nil
        case .cellularDenied: String(localized: "Mobile data is off for Pingscape")
        case .wifiDenied: String(localized: "Wi-Fi is not allowed for Pingscape")
        case .localNetworkDenied: String(localized: "Local network access is not allowed")
        case .vpnInactive: String(localized: "The VPN is not active")
        }
    }
}
