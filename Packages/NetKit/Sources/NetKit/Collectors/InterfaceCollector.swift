import Darwin

/// Reads all network interfaces with their addresses (`getifaddrs`).
public enum InterfaceCollector {
    private struct Builder {
        var flags: InterfaceFlags
        var mtu: Int?
        var addresses: [InterfaceAddress] = []
    }

    public static func collect() -> [NetworkInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }

        var order: [String] = []
        var builders: [String: Builder] = [:]
        let counters = InterfaceCounterCollector.collect()

        var cursor = head
        while let entry = cursor {
            let ifa = entry.pointee
            cursor = ifa.ifa_next
            let name = String(cString: ifa.ifa_name)

            if builders[name] == nil {
                order.append(name)
                builders[name] = Builder(flags: InterfaceFlags(rawValue: ifa.ifa_flags))
            }
            guard let sa = ifa.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)

            if family == AF_LINK {
                // The 32-bit counters in `if_data` wrap after 4 GiB, so only the
                // MTU is read here. The counters come from `InterfaceCounterCollector`.
                if let data = ifa.ifa_data {
                    builders[name]?.mtu = Int(data.assumingMemoryBound(to: if_data.self).pointee.ifi_mtu)
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
            let traffic = counters[Int(if_nametoindex(name))]
            return NetworkInterface(
                name: name,
                isUp: builder.flags.contains(.up),
                flags: builder.flags,
                mtu: builder.mtu,
                addresses: builder.addresses,
                receivedBytes: traffic?.receivedBytes,
                sentBytes: traffic?.sentBytes,
                receivedPackets: traffic?.receivedPackets,
                sentPackets: traffic?.sentPackets)
        }
    }
}
