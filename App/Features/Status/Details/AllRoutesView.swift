import NetKit
import SwiftUI

/// The complete routing table, read from the system when the page opens.
struct AllRoutesView: View {
    @State private var routes: [RouteEntry]?

    var body: some View {
        DetailPage(title: "All routes") {
            if let routes {
                let v4 = Self.sorted(routes.filter { !$0.isIPv6 })
                let v6 = Self.sorted(routes.filter(\.isIPv6))
                if !v4.isEmpty {
                    InfoSection(title: "IPv4") {
                        ForEach(v4) { RouteEntryRow(route: $0) }
                    }
                }
                if !v6.isEmpty {
                    InfoSection(title: "IPv6") {
                        ForEach(v6) { RouteEntryRow(route: $0) }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task {
            routes = await Task.detached { RouteCollector.allRoutes() }.value
        }
    }

    /// The default route first, then by address.
    static func sorted(_ routes: [RouteEntry]) -> [RouteEntry] {
        routes.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            if let a = IPv4.toInt(lhs.destination), let b = IPv4.toInt(rhs.destination), a != b { return a < b }
            return lhs.destination.localizedStandardCompare(rhs.destination) == .orderedAscending
        }
    }
}

/// One route: destination, interface, gateway and flags.
private struct RouteEntryRow: View {
    @Environment(PrivacyMask.self) private var mask
    let route: RouteEntry

    private var destination: String { route.isDefault ? String(localized: "default") : route.destinationWithPrefix }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    destinationText
                    Spacer(minLength: 8)
                    interfaceText
                }
                VStack(alignment: .leading, spacing: 2) {
                    destinationText
                    interfaceText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                if let gateway = route.gateway {
                    Text("via \(mask.shown(gateway))")
                }
                Text(verbatim: route.flags)
            }
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu { RowCopyMenu(value: valueText) }
        .accessibilityElement(children: .combine)
        .recordRow(
            label: LocalizedStringResource(stringLiteral: route.isDefault ? destination : mask.shown(destination)),
            value: valueText, sensitive: route.gateway != nil)
    }

    private var destinationText: some View {
        Text(route.isDefault ? destination : mask.shown(destination))
            .font(.system(.body, design: .monospaced))
    }

    private var interfaceText: some View {
        Text(verbatim: route.interfaceName)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    /// For copying: gateway, interface and flags, as `netstat -rn` orders them.
    private var valueText: String {
        [route.gateway.map { "via \($0)" }, route.interfaceName, route.flags]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
