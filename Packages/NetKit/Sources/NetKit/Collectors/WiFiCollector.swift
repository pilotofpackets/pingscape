#if os(iOS)
import Foundation
import NetworkExtension

/// Reads the connected Wi-Fi network.
///
/// Needs the "Access WiFi Information" capability and, for the SSID, location
/// permission while in use. Nothing beyond what `NEHotspotNetwork` returns is
/// read or guessed.
public enum WiFiCollector {
    public static func collect(
        interfaces: [NetworkInterface],
        locationAuthorized: Bool
    ) async -> Availability<WiFiInfo> {
        if let network = await NEHotspotNetwork.fetchCurrent() {
            return .value(
                WiFiInfo(
                    ssid: network.ssid,
                    bssid: MACAddress.canonical(network.bssid),
                    security: security(network.securityType),
                    didAutoJoin: network.didAutoJoin,
                    didJustJoin: network.didJustJoin))
        }
        let hasWiFiAddress = interfaces.contains { $0.kind == .wifi && $0.isUp && $0.hasUsableAddress }
        // An address on en0 without an SSID almost always means the location
        // permission is missing. Without an address there is no connection.
        guard hasWiFiAddress else { return .none }
        return locationAuthorized ? .none : .needsPermission(.location)
    }

    private static func security(_ type: NEHotspotNetworkSecurityType) -> WiFiSecurity {
        switch type {
        case .open: .open
        case .WEP: .wep
        case .personal: .personal
        case .enterprise: .enterprise
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }
}
#endif
