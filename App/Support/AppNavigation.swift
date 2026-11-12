import Foundation
import Observation

enum ToolKind: String, CaseIterable, Identifiable {
    case ping, traceroute, dns, whois, ports, tls, http, nat, ntp, dualstack, subnet, oui

    var id: String { rawValue }
}

/// A tool to open with its target already filled in, from a device in the LAN list.
struct ToolRequest: Equatable {
    let id = UUID()
    let tool: ToolKind
    let target: String

    static func == (lhs: ToolRequest, rhs: ToolRequest) -> Bool { lhs.id == rhs.id }
}

/// Which tab is open, and requests from one tab to another.
@MainActor
@Observable
final class AppNavigation {
    var tab: AppTab = DemoLaunch.tab
    var toolRequest: ToolRequest?
    /// A page of the overview to show, from another tab.
    var overviewRequest: OverviewDestination?

    func openOverview(_ destination: OverviewDestination) {
        overviewRequest = destination
        tab = .overview
    }

    func open(_ tool: ToolKind, target: String) {
        toolRequest = ToolRequest(tool: tool, target: target)
        tab = .tools
    }

    /// A page from a deep link. A tool opens with its field as it was.
    func open(_ page: AppPage) {
        switch page {
        case .overview: tab = .overview
        case .lan: tab = .lan
        case .live: tab = .live
        default:
            if let tool = ToolKind(rawValue: page.rawValue) { open(tool, target: "") }
        }
    }
}
