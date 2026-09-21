import Foundation

/// Launch arguments for the demo mode, for screenshots and UI checks.
enum DemoLaunch {
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    /// The value after a launch argument such as `-demo-tool ping`. Only in demo mode.
    static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-demo"), let index = arguments.firstIndex(of: flag), index + 1 < arguments.count
        else { return nil }
        return arguments[index + 1]
    }

    /// `-demo -demo-tool dns` opens the Tools tab on that tool.
    static var tool: ToolKind? { value(after: "-demo-tool").flatMap(ToolKind.init(rawValue:)) }

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
            case "external": .external
            case "routes": .allRoutes
            default:
                part.hasPrefix("interface:") ? .interface(String(part.dropFirst("interface:".count))) : nil
            }
        }
    }
}
