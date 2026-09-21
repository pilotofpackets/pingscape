import Foundation
import NetKit

/// The network status as text, for the Shortcuts action. Same labels and the
/// same layout as the report you can share from the overview.
@MainActor
enum StatusText {
    static func make(_ snapshot: NetworkSnapshot, at date: Date = Date()) -> String {
        let masked = UserDefaults.standard.bool(forKey: PrivacyMask.hideByDefaultKey)
        var sections: [ReportSection] = []

        var connection: [ReportRow] = [
            ReportRow(
                label: String(localized: "Status"),
                value: snapshot.isOnline ? String(localized: "Online") : String(localized: "Offline"), isSensitive: false)
        ]
        if snapshot.isOnline, snapshot.connectionKind != .other {
            connection.append(ReportRow(label: String(localized: "Active via"), value: snapshot.connectionKind.label, isSensitive: false))
        }
        if let ipv4 = snapshot.primaryIPv4 {
            connection.append(ReportRow(label: String(localized: "IP address"), value: ipv4.ip, isSensitive: true))
            if let mask = ipv4.netmask ?? ipv4.prefixLength.map(IPv4.netmask(fromPrefix:)) {
                connection.append(ReportRow(label: String(localized: "Subnet mask"), value: mask, isSensitive: true))
            }
        }
        if let gateway = snapshot.localGateway4 {
            connection.append(ReportRow(label: String(localized: "Default gateway"), value: gateway, isSensitive: true))
        }
        if let ipv6 = snapshot.primaryIPv6 {
            connection.append(ReportRow(label: String(localized: "IPv6 address"), value: ipv6.withPrefix, isSensitive: true))
        }
        if !snapshot.dnsServers.isEmpty {
            connection.append(
                ReportRow(label: String(localized: "DNS servers"), value: snapshot.dnsServers.joined(separator: "\n"), isSensitive: true))
        }
        sections.append(ReportSection(title: String(localized: "Connection"), rows: connection))

        // The Wi-Fi name needs the location permission, which a Shortcut may not have.
        // Without the name the rows are simply not there.
        if case .value(let wifi) = snapshot.wifi {
            var rows = [ReportRow(label: String(localized: "Name (SSID)"), value: wifi.ssid, isSensitive: true)]
            if let bssid = wifi.bssid { rows.append(ReportRow(label: "BSSID", value: bssid, isSensitive: true)) }
            if let security = wifi.security.label { rows.append(ReportRow(label: String(localized: "Security"), value: security, isSensitive: false)) }
            sections.append(ReportSection(title: String(localized: "Wi-Fi"), rows: rows))
        }

        if let scope = snapshot.tunnelScope {
            var rows = [
                ReportRow(
                    label: String(localized: "Status"),
                    value: scope == .full ? String(localized: "Active · Full tunnel") : String(localized: "Active · Split tunnel"),
                    isSensitive: false)
            ]
            for tunnel in snapshot.vpnInterfaces {
                rows.append(ReportRow(label: String(localized: "Interface"), value: tunnel.name, isSensitive: false))
                if let address = tunnel.ipv4Addresses.first ?? tunnel.ipv6Addresses.first {
                    rows.append(ReportRow(label: String(localized: "IP address"), value: address.ip, isSensitive: true))
                }
            }
            sections.append(ReportSection(title: String(localized: "VPN and Tunnel"), rows: rows))
        }

        let services = snapshot.knownCellularServices
        if !services.isEmpty {
            sections.append(
                ReportSection(
                    title: String(localized: "Cellular"),
                    rows: services.map {
                        ReportRow(label: String($0.title(among: snapshot.cellularServices.count).localizedString), value: $0.technology.label, isSensitive: false)
                    }))
        }
        return ReportFormatter.text(header: DeviceInfo.reportHeader(at: date), sections: sections, masked: masked)
    }
}

extension LocalizedStringResource {
    /// The text in the current language.
    var localizedString: String { String(localized: self) }
}
