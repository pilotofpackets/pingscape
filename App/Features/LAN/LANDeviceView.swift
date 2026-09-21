import NetKit
import SwiftUI

/// One device of the LAN list: what is known about it, and shortcuts to the
/// tools with its address filled in.
struct LANDeviceView: View {
    @Environment(SnapshotStore.self) private var store
    @Environment(LANModel.self) private var lan
    @Environment(AppNavigation.self) private var navigation
    @Environment(PrivacyMask.self) private var mask
    let ip: String

    private var device: LANDevice? { lan.list.devices.first { $0.ip == ip } }

    var body: some View {
        // The address and the names in titles are as hidden as the rows.
        DetailPage(title: LocalizedStringResource(stringLiteral: mask.shown(ip))) {
            if let device {
                deviceSection(device)
                ForEach(Array(device.services.enumerated()), id: \.offset) { _, service in
                    serviceSection(service)
                }
                if ip == store.snapshot?.localGateway4, let info = lan.routerInfo { routerSection(info) }
                actions
            }
        }
    }

    private func deviceSection(_ device: LANDevice) -> some View {
        InfoSection(title: "Device") {
            if let name = device.displayName { DataRow(label: "Name", value: name, sensitive: true) }
            DataRow(label: "IP address", value: device.ip, monospaced: true, sensitive: true)
            if let hostname = device.hostname { DataRow(label: "Host name", value: hostname, sensitive: true) }
            if let mac = device.macAddress {
                DataRow(label: "MAC address", value: mac, monospaced: true, sensitive: true)
                if let vendor = store.oui.vendor(forMAC: mac) { DataRow(label: "Vendor", value: vendor) }
            }
            if let latency = device.latencyMilliseconds { DataRow(label: "Latency", value: milliseconds(latency)) }
            if device.services.isEmpty, device.answeredPing, device.displayName == nil {
                DataRow(label: "Status", value: String(localized: "Answers to ping"))
            }
            if !device.openPorts.isEmpty {
                DataRow(label: "Open ports", value: device.openPorts.map(String.init).joined(separator: " · "), monospaced: true)
            }
        }
    }

    private func serviceSection(_ service: LANService) -> some View {
        InfoSection(title: LocalizedStringResource(stringLiteral: mask.shown(service.displayName))) {
            DataRow(label: "Service", value: service.type, monospaced: true)
            if let port = service.port { DataRow(label: "Port", value: String(port), monospaced: true) }
            // The entries as the device delivers them. Nothing is interpreted.
            ForEach(service.txt.sorted { $0.key < $1.key }, id: \.key) { entry in
                DataRow(
                    label: LocalizedStringResource(stringLiteral: entry.key), value: entry.value, monospaced: true,
                    sensitive: Self.identifyingKeys.contains(entry.key.lowercased()), stacked: true)
            }
        }
    }

    /// TXT entries that hold an address or a device identifier.
    private static let identifyingKeys: Set<String> = ["deviceid", "id", "macaddress", "psi", "pi", "serialnumber", "sn"]

    private func routerSection(_ info: RouterInfo) -> some View {
        InfoSection(title: "Router (UPnP)") {
            if let manufacturer = info.manufacturer { DataRow(label: "Manufacturer", value: manufacturer) }
            if let model = info.model { DataRow(label: "Model", value: model) }
            if let firmware = info.firmware { DataRow(label: "Firmware", value: firmware) }
            if let externalIP = info.externalIP {
                DataRow(label: "WAN address", value: externalIP, monospaced: true, sensitive: true)
            }
            if let uptime = info.uptimeSeconds {
                DataRow(
                    label: "Uptime",
                    value: Duration.seconds(uptime).formatted(
                        .units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))
            }
        }
    }

    private var actions: some View {
        InfoSection(title: "Actions") {
            ActionRow(title: "Ping", symbol: "dot.radiowaves.left.and.right") { navigation.open(.ping, target: ip) }
            ActionRow(title: "Check ports", symbol: "door.left.hand.open") { navigation.open(.ports, target: ip) }
            ActionRow(title: "Traceroute", symbol: "point.topleft.down.to.point.bottomright.curvepath") {
                navigation.open(.traceroute, target: ip)
            }
        }
    }
}

private struct ActionRow: View {
    let title: LocalizedStringResource
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 24).foregroundStyle(.tint).accessibilityHidden(true)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
