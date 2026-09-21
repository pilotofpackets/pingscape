import NetKit
import SwiftUI

struct RoutingView: View {
    @Environment(SnapshotStore.self) private var store

    var body: some View {
        DetailPage(title: "Routing") {
            if let snapshot = store.snapshot {
                if let path = snapshot.path {
                    InfoSection(title: "System path") {
                        StatusRow(
                            label: "Status",
                            text: path.isOnline ? String(localized: "Online") : String(localized: "Offline"),
                            tone: path.isOnline ? .good : .critical)
                        if let active = Self.activeInterface(snapshot) {
                            DataRow(label: "Active via", value: active)
                        }
                        // Only what is set. A "No" would be noise.
                        if path.isExpensive {
                            DataRow(label: "Metered connection", value: String(localized: "Yes"))
                        }
                        if path.isConstrained {
                            DataRow(label: "Low Data Mode", value: String(localized: "On"))
                        }
                        // The system's own list, next to the table below. If the two
                        // differ, both are shown, without a comment.
                        if !path.gateways.isEmpty {
                            DataRow(
                                label: "Gateways per system", value: path.gateways.joined(separator: "\n"),
                                monospaced: true, sensitive: true)
                        }
                    }
                }
                let routes = Self.sorted(snapshot.defaultRoutes)
                if !routes.isEmpty {
                    InfoSection(title: "Default routes") {
                        ForEach(routes, id: \.self) { RouteRow(route: $0) }
                        LinkRow(label: "All routes", value: OverviewDestination.allRoutes)
                    }
                }
            }
        }
    }

    /// The interface whose default route carries the traffic, with what it is.
    static func activeInterface(_ snapshot: NetworkSnapshot) -> String? {
        guard let name = snapshot.defaultRoutes.first(where: { $0.isActive && !$0.isIPv6 })?.interfaceName
            ?? snapshot.defaultRoutes.first(where: \.isActive)?.interfaceName
        else { return nil }
        let kind = snapshot.interfaces.first { $0.name == name }?.kind
        if let label = kind?.label { return "\(label) (\(name))" }
        return name
    }

    /// IPv4 before IPv6, and within one family the route that carries the
    /// traffic first.
    static func sorted(_ routes: [DefaultRoute]) -> [DefaultRoute] {
        routes.sorted { lhs, rhs in
            if lhs.isIPv6 != rhs.isIPv6 { return !lhs.isIPv6 }
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.interfaceName.localizedStandardCompare(rhs.interfaceName) == .orderedAscending
        }
    }
}

/// One default route: family, interface, gateway and whether it carries traffic.
private struct RouteRow: View {
    let route: DefaultRoute

    private var family: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: route.isIPv6 ? "IPv6" : "IPv4")
            Text(verbatim: route.interfaceName)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var carriesTraffic: some View {
        if route.isActive {
            HStack(spacing: 6) {
                StatusDot(tone: .good)
                Text("Carries traffic")
            }
            .font(.footnote)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    family
                    Spacer(minLength: 8)
                    carriesTraffic
                }
                VStack(alignment: .leading, spacing: 4) {
                    family
                    carriesTraffic
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let gateway = route.gateway {
                DataRowValue(label: "Gateway", value: gateway)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu { RowCopyMenu(value: summary) }
        .accessibilityElement(children: .combine)
        .recordRow(
            label: LocalizedStringResource(stringLiteral: "\(route.isIPv6 ? "IPv6" : "IPv4") \(route.interfaceName)"),
            value: summary, sensitive: route.gateway != nil)
    }

    private var summary: String {
        [route.gateway.map { "via \($0)" }, route.isActive ? String(localized: "Carries traffic") : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// A small label-and-value pair inside a row that has its own heading.
private struct DataRowValue: View {
    @Environment(PrivacyMask.self) private var mask
    let label: LocalizedStringKey
    let value: String

    private var labelText: some View {
        Text(label).font(.footnote).foregroundStyle(.secondary)
    }

    private var valueText: some View {
        Text(mask.shown(value))
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                labelText
                valueText
            }
            VStack(alignment: .leading, spacing: 2) {
                labelText
                valueText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
