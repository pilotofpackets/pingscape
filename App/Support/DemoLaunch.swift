import Foundation

/// Launch arguments for the demo mode, for screenshots and UI checks.
enum DemoLaunch {
    /// `-demo -demo-tab about` starts on that tab. Without `-demo` it is ignored.
    static var tab: AppTab {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-demo"),
            let flag = arguments.firstIndex(of: "-demo-tab"), flag + 1 < arguments.count
        else { return .overview }
        return AppTab(rawValue: arguments[flag + 1]) ?? .overview
    }

    /// `-demo -demo-path wifi,interface:utun4` opens the overview and pushes
    /// those pages. Without `-demo` the argument is ignored.
    static var overviewPath: [OverviewDestination] {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-demo"),
            let flag = arguments.firstIndex(of: "-demo-path"), flag + 1 < arguments.count
        else { return [] }
        return arguments[flag + 1].split(separator: ",").compactMap { part in
            switch part {
            case "wifi": .wifi
            case "vpn": .vpn
            case "cellular": .cellular
            case "routing": .routing
            case "dns": .dns
            case "interfaces": .interfaces
            default:
                part.hasPrefix("interface:") ? .interface(String(part.dropFirst("interface:".count))) : nil
            }
        }
    }
}
