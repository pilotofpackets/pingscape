import Darwin

/// Reads all network interfaces with their addresses (`getifaddrs`).
public enum InterfaceCollector {
    private struct Builder {
        var isUp: Bool
        var mtu: Int?
        var received: UInt64?
        var sent: UInt64?
        var addresses: [InterfaceAddress] = []
    }

    public static func collect() -> [NetworkInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }

        var order: [String] = []
        var builders: [String: Builder] = [:]

        var cursor = head
        while let entry = cursor {
            let ifa = entry.pointee
            cursor = ifa.ifa_next
            let name = String(cString: ifa.ifa_name)

            if builders[name] == nil {
                order.append(name)
                builders[name] = Builder(isUp: (ifa.ifa_flags & UInt32(IFF_UP)) != 0)
            }
            guard let sa = ifa.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)

            if family == AF_LINK {
                if let data = ifa.ifa_data {
                    let counters = data.assumingMemoryBound(to: if_data.self).pointee
                    builders[name]?.mtu = Int(counters.ifi_mtu)
                    builders[name]?.received = UInt64(counters.ifi_ibytes)
                    builders[name]?.sent = UInt64(counters.ifi_obytes)
                }
                continue
            }

            guard family == AF_INET || family == AF_INET6, let ip = SocketAddress.numericHost(sa)
            else { continue }

            var prefix: Int?
            var netmask: String?
            if let mask = ifa.ifa_netmask {
                prefix = SocketAddress.prefixLength(mask)
                if family == AF_INET { netmask = SocketAddress.numericHost(mask) }
            }
            builders[name]?.addresses.append(
                InterfaceAddress(ip: ip, isIPv6: family == AF_INET6, prefixLength: prefix, netmask: netmask))
        }

        return order.compactMap { name in
            guard let builder = builders[name] else { return nil }
            return NetworkInterface(
                name: name,
                isUp: builder.isUp,
                mtu: builder.mtu,
                addresses: builder.addresses,
                receivedBytes: builder.received,
                sentBytes: builder.sent)
        }
    }
}
