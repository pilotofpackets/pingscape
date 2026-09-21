/// The pages the overview leads to.
enum OverviewDestination: Hashable {
    case wifi
    case vpn
    case cellular
    case routing
    case dns
    case interfaces
    case external
    case allRoutes
    case interface(String)
}
