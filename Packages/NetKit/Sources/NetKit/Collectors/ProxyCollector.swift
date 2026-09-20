import CFNetwork
import Foundation

/// Reads the system proxy settings and the tunnel services the system knows.
public enum ProxyCollector {
    public struct Report: Sendable {
        public let proxy: ProxyInfo
        /// Tunnel interfaces listed under `__SCOPED__`. iOS creates interface
        /// bound settings for every active VPN service. The carrier's IPsec
        /// tunnel for Wi-Fi Calling is not a user service and is missing there.
        public let vpnServiceInterfaces: Set<String>
    }

    public static func collect() -> Report {
        guard
            let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
        else {
            return Report(proxy: ProxyInfo(), vpnServiceInterfaces: [])
        }
        return Report(proxy: proxy(from: settings), vpnServiceInterfaces: tunnelServices(from: settings))
    }

    static func proxy(from settings: [String: Any]) -> ProxyInfo {
        // The constants are only partly exported on iOS, so these are the
        // strings CFNetwork actually returns.
        if (settings["ProxyAutoConfigEnable"] as? NSNumber)?.intValue == 1,
            let pac = settings["ProxyAutoConfigURLString"] as? String, !pac.isEmpty
        {
            return ProxyInfo(isEnabled: true, pacURL: pac)
        }
        if (settings["HTTPEnable"] as? NSNumber)?.intValue == 1,
            let host = settings["HTTPProxy"] as? String, !host.isEmpty
        {
            return ProxyInfo(
                isEnabled: true, host: host, port: (settings["HTTPPort"] as? NSNumber)?.intValue)
        }
        return ProxyInfo()
    }

    static func tunnelServices(from settings: [String: Any]) -> Set<String> {
        guard let scoped = settings["__SCOPED__"] as? [String: Any] else { return [] }
        let prefixes = ["utun", "ipsec", "ppp", "tun", "tap"]
        return Set(scoped.keys.filter { name in prefixes.contains { name.hasPrefix($0) } })
    }
}
