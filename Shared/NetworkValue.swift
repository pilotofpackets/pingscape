import AppIntents
import Foundation
import NetKit

// Compiled into the app and into the widget extension, so Shortcuts, Siri and
// the widgets read every value the same way. Only values the device itself
// knows: the public address and the provider need a request to the internet
// and the user's consent, which the widget cannot see (see
// `NetworkQuery` in the app).

/// One value of the current network state.
enum NetworkValue: String, AppEnum, CaseIterable, Sendable {
    case connection
    case interface
    case localIPv4
    case subnetMask
    case localIPv6
    case gateway
    case gatewayIPv6
    case dnsServers
    case wifiName
    case bssid
    case wifiSecurity
    case vpn
    case vpnInterface
    case vpnAddress
    case cellular
    case mtu
    case lowDataMode

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Network value"

    static let caseDisplayRepresentations: [NetworkValue: DisplayRepresentation] = [
        .connection: DisplayRepresentation(title: "Connection", image: .init(systemName: "network")),
        .interface: DisplayRepresentation(title: "Active interface", image: .init(systemName: "cable.connector")),
        .localIPv4: DisplayRepresentation(title: "IP address", image: .init(systemName: "number")),
        .subnetMask: DisplayRepresentation(title: "Subnet mask", image: .init(systemName: "square.grid.3x3")),
        .localIPv6: DisplayRepresentation(title: "IPv6 address", image: .init(systemName: "number")),
        .gateway: DisplayRepresentation(title: "Default gateway", image: .init(systemName: "arrow.triangle.branch")),
        .gatewayIPv6: DisplayRepresentation(title: "IPv6 gateway", image: .init(systemName: "arrow.triangle.branch")),
        .dnsServers: DisplayRepresentation(title: "DNS servers", image: .init(systemName: "server.rack")),
        .wifiName: DisplayRepresentation(title: "Wi-Fi name", image: .init(systemName: "wifi")),
        .bssid: DisplayRepresentation(title: "BSSID", image: .init(systemName: "wifi.router")),
        .wifiSecurity: DisplayRepresentation(title: "Wi-Fi security", image: .init(systemName: "lock")),
        .vpn: DisplayRepresentation(title: "VPN status", image: .init(systemName: "lock.shield")),
        .vpnInterface: DisplayRepresentation(title: "VPN interface", image: .init(systemName: "lock.shield")),
        .vpnAddress: DisplayRepresentation(title: "VPN address", image: .init(systemName: "lock.shield")),
        .cellular: DisplayRepresentation(
            title: "Cellular technology", image: .init(systemName: "antenna.radiowaves.left.and.right")),
        .mtu: DisplayRepresentation(title: "Interface MTU", image: .init(systemName: "ruler")),
        .lowDataMode: DisplayRepresentation(title: "Low Data Mode", image: .init(systemName: "tortoise")),
    ]

    /// The name in the current language, as a label next to the value.
    var title: String {
        String(localized: Self.caseDisplayRepresentations[self]?.title ?? "\(rawValue)")
    }

    var symbol: String {
        switch self {
        case .connection: "network"
        case .interface: "cable.connector"
        case .localIPv4, .localIPv6: "number"
        case .subnetMask: "square.grid.3x3"
        case .gateway, .gatewayIPv6: "arrow.triangle.branch"
        case .dnsServers: "server.rack"
        case .wifiName: "wifi"
        case .bssid: "wifi.router"
        case .wifiSecurity: "lock"
        case .vpn, .vpnInterface, .vpnAddress: "lock.shield"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .mtu: "ruler"
        case .lowDataMode: "tortoise"
        }
    }

    /// Addresses and network names: hidden by "Hide values" and on a locked
    /// Lock Screen, like the rows marked sensitive in the app.
    var isSensitive: Bool {
        switch self {
        case .localIPv4, .subnetMask, .localIPv6, .gateway, .gatewayIPv6, .dnsServers, .wifiName, .bssid,
            .vpnAddress:
            true
        case .connection, .interface, .wifiSecurity, .vpn, .vpnInterface, .cellular, .mtu, .lowDataMode:
            false
        }
    }
}

/// What a value is when it is not there.
enum NetworkValueMissing: Error, Sendable, Equatable {
    /// The device has no such value right now (no IPv6, no VPN, no Wi-Fi).
    case notPresent
    /// iOS gives the Wi-Fi name and BSSID only with the location permission.
    case needsLocation
}

extension NetworkValue {
    /// The value as text, one line per item (several DNS servers, several
    /// tunnels). Never a guess: what the snapshot does not hold is missing.
    func read(from snapshot: NetworkSnapshot) -> Result<[String], NetworkValueMissing> {
        let values: [String]
        switch self {
        case .connection:
            values = [snapshot.isOnline ? connectionName(snapshot.connectionKind) : String(localized: "Offline")]
        case .interface:
            values = [snapshot.primaryInterface?.name].compactMap { $0 }
        case .localIPv4:
            values = [snapshot.primaryIPv4?.ip].compactMap { $0 }
        case .subnetMask:
            let address = snapshot.primaryIPv4
            values = [address?.netmask ?? address?.prefixLength.map(IPv4.netmask(fromPrefix:))].compactMap { $0 }
        case .localIPv6:
            values = [snapshot.primaryIPv6?.ip].compactMap { $0 }
        case .gateway:
            values = [snapshot.localGateway4].compactMap { $0 }
        case .gatewayIPv6:
            values = [snapshot.localGateway6].compactMap { $0 }
        case .dnsServers:
            values = snapshot.dnsServers
        case .wifiName, .bssid, .wifiSecurity:
            switch snapshot.wifi {
            case .value(let wifi):
                values =
                    switch self {
                    case .wifiName: [wifi.ssid]
                    case .bssid: [wifi.bssid].compactMap { $0 }
                    default: [securityName(wifi.security)].compactMap { $0 }
                    }
            case .needsPermission(.location):
                return .failure(.needsLocation)
            default:
                values = []
            }
        case .vpn:
            let status: String =
                switch snapshot.tunnelScope {
                case .full: String(localized: "Active · Full tunnel")
                case .partial: String(localized: "Active · Split tunnel")
                case nil: String(localized: "Not active")
                }
            values = [status]
        case .vpnInterface:
            values = snapshot.vpnInterfaces.map(\.name)
        case .vpnAddress:
            values = snapshot.vpnInterfaces.compactMap { ($0.ipv4Addresses.first ?? $0.ipv6Addresses.first)?.ip }
        case .cellular:
            let known = snapshot.cellularServices.filter { $0.technology != .unknown }
            values = [(known.first(where: \.isDataService) ?? known.first)?.technology.label].compactMap { $0 }
        case .mtu:
            values = [snapshot.primaryInterface?.mtu.map(String.init)].compactMap { $0 }
        case .lowDataMode:
            values = [snapshot.path.map { $0.isConstrained ? String(localized: "On") : String(localized: "Off") }]
                .compactMap { $0 }
        }
        return values.isEmpty ? .failure(.notPresent) : .success(values)
    }

    /// The sentence for "there is no such value", for Siri and widgets.
    var missingText: String {
        switch self {
        case .connection, .vpn, .lowDataMode: String(localized: "The system did not report it")
        case .interface, .localIPv4, .subnetMask, .mtu: String(localized: "No local connection right now")
        case .localIPv6: String(localized: "No IPv6 address right now")
        case .gateway, .gatewayIPv6: String(localized: "No local gateway right now")
        case .dnsServers: String(localized: "No DNS servers right now")
        case .wifiName, .bssid, .wifiSecurity: String(localized: "Not connected to Wi-Fi")
        case .vpnInterface, .vpnAddress: String(localized: "No VPN is active")
        case .cellular: String(localized: "No cellular connection right now")
        }
    }
}

// Own wording instead of the app's `label` extensions, which the widget does
// not have. Same strings, so the translations are shared.

private func connectionName(_ kind: ConnectionKind) -> String {
    switch kind {
    case .wifi: String(localized: "Wi-Fi")
    case .cellular: String(localized: "Cellular")
    case .ethernet: String(localized: "Ethernet")
    case .other: String(localized: "Other")
    case .offline: String(localized: "Offline")
    }
}

private func securityName(_ security: WiFiSecurity) -> String? {
    switch security {
    case .open: String(localized: "Open")
    case .wep: "WEP"
    case .personal: "WPA2/WPA3 Personal"
    case .enterprise: "WPA2/WPA3 Enterprise"
    case .unknown: nil
    }
}

/// A page of the app, for deep links from widgets and Control Center.
/// `pingscape://tools/ping` opens the ping tool.
enum AppPage: String, AppEnum, CaseIterable, Sendable {
    case overview, lan, live, ping, traceroute, dns, whois, ports, tls, http, nat, ntp, dualstack, subnet, oui

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Page"

    static let caseDisplayRepresentations: [AppPage: DisplayRepresentation] = [
        .overview: DisplayRepresentation(title: "Overview", image: .init(systemName: "square.grid.2x2")),
        .lan: DisplayRepresentation(title: "LAN", image: .init(systemName: "network")),
        .live: DisplayRepresentation(title: "Live", image: .init(systemName: "waveform.path.ecg")),
        .ping: DisplayRepresentation(title: "Ping", image: .init(systemName: "dot.radiowaves.left.and.right")),
        .traceroute: DisplayRepresentation(title: "Traceroute", image: .init(systemName: "point.topleft.down.to.point.bottomright.curvepath")),
        .dns: DisplayRepresentation(title: "DNS", image: .init(systemName: "server.rack")),
        .whois: DisplayRepresentation(title: "Whois", image: .init(systemName: "person.text.rectangle")),
        .ports: DisplayRepresentation(title: "Ports", image: .init(systemName: "door.left.hand.open")),
        .tls: DisplayRepresentation(title: "TLS certificate", image: .init(systemName: "lock.doc")),
        .http: DisplayRepresentation(title: "HTTP timing", image: .init(systemName: "stopwatch")),
        .nat: DisplayRepresentation(title: "NAT", image: .init(systemName: "arrow.left.arrow.right")),
        .ntp: DisplayRepresentation(title: "NTP", image: .init(systemName: "clock")),
        .dualstack: DisplayRepresentation(title: "Dual stack", image: .init(systemName: "arrow.triangle.swap")),
        .subnet: DisplayRepresentation(title: "Subnet", image: .init(systemName: "square.grid.3x3")),
        .oui: DisplayRepresentation(title: "OUI", image: .init(systemName: "barcode")),
    ]

    static let scheme = "pingscape"

    var url: URL {
        switch self {
        case .overview, .lan, .live: URL(string: "\(Self.scheme)://\(rawValue)")!
        default: URL(string: "\(Self.scheme)://tools/\(rawValue)")!
        }
    }

    var title: String {
        String(localized: Self.caseDisplayRepresentations[self]?.title ?? "\(rawValue)")
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .lan: "network"
        case .live: "waveform.path.ecg"
        case .ping: "dot.radiowaves.left.and.right"
        case .traceroute: "point.topleft.down.to.point.bottomright.curvepath"
        case .dns: "server.rack"
        case .whois: "person.text.rectangle"
        case .ports: "door.left.hand.open"
        case .tls: "lock.doc"
        case .http: "stopwatch"
        case .nat: "arrow.left.arrow.right"
        case .ntp: "clock"
        case .dualstack: "arrow.triangle.swap"
        case .subnet: "square.grid.3x3"
        case .oui: "barcode"
        }
    }

    /// The page a deep link names, `nil` for anything else.
    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        let name = host == "tools" ? url.pathComponents.dropFirst().first ?? "" : host
        guard let page = AppPage(rawValue: name) else { return nil }
        self = page
    }
}
