import Darwin

/// Parses a routing table dump (`sysctl NET_RT_DUMP`) into default routes.
///
/// `net/route.h` is not part of the iOS SDK, so the message layout is spelled
/// out here. It is part of the stable Darwin ABI: `sizeof(struct rt_msghdr)` is
/// 92, `rtm_msglen` sits at offset 0, `rtm_index` at 4, `rtm_flags` at 8 and
/// `rtm_addrs` at 12. The socket addresses follow the header. The parser works
/// on plain bytes so tests can feed it recorded or hand-built buffers.
public enum RouteMessageParser {
    static let headerSize = 92
    static let flagUp: Int32 = 0x1
    static let flagGateway: Int32 = 0x2
    static let flagHost: Int32 = 0x4
    static let flagReject: Int32 = 0x8
    static let flagBlackhole: Int32 = 0x1000
    static let flagInterfaceScope: Int32 = 0x100_0000
    static let addrDestination: Int32 = 0x1

    public static func defaultRoutes(
        in buffer: [UInt8],
        isIPv6: Bool,
        interfaceName: (Int) -> String?
    ) -> [DefaultRoute] {
        func u16(_ offset: Int) -> Int {
            Int(buffer[offset]) | (Int(buffer[offset + 1]) << 8)
        }
        func i32(_ offset: Int) -> Int32 {
            var value: UInt32 = 0
            for byte in 0..<4 { value |= UInt32(buffer[offset + byte]) << (8 * UInt32(byte)) }
            return Int32(bitPattern: value)
        }

        var routes: [DefaultRoute] = []
        var offset = 0
        while offset + headerSize <= buffer.count {
            let length = u16(offset)
            if length < headerSize || offset + length > buffer.count { break }
            defer { offset += length }

            let index = u16(offset + 4)
            let flags = i32(offset + 8)
            let addrs = i32(offset + 12)
            guard flags & flagUp != 0,
                flags & (flagReject | flagBlackhole | flagHost) == 0,
                addrs & addrDestination != 0
            else { continue }

            var cursor = offset + headerSize
            var isDefault = false
            var gateway: String?

            // Destination is bit 0, gateway bit 1. Nothing else is needed.
            for bit in 0..<2 {
                guard addrs & (1 << Int32(bit)) != 0 else { continue }
                guard cursor + 1 < offset + length else { break }
                let saLength = Int(buffer[cursor])
                if bit == 0 {
                    isDefault = isUnspecified(buffer, at: cursor, end: offset + length)
                } else if flags & flagGateway != 0 {
                    // Without RTF_GATEWAY this is a link address, not a router.
                    gateway = address(buffer, at: cursor, end: offset + length)
                }
                cursor += saLength > 0 ? (saLength + 3) & ~3 : 4
            }

            guard isDefault, let name = interfaceName(index) else { continue }
            routes.append(
                DefaultRoute(
                    interfaceName: name,
                    gateway: (gateway?.isEmpty ?? true) ? nil : gateway,
                    isIPv6: isIPv6,
                    isActive: flags & flagInterfaceScope == 0))
        }
        return routes
    }

    /// A default route can also be written with `sa_len` 0.
    private static func isUnspecified(_ buffer: [UInt8], at start: Int, end: Int) -> Bool {
        let length = Int(buffer[start])
        if length == 0 { return true }
        switch Int32(buffer[start + 1]) {
        case AF_INET:
            guard start + 8 <= end else { return false }
            return buffer[(start + 4)..<(start + 8)].allSatisfy { $0 == 0 }
        case AF_INET6:
            guard start + 24 <= end else { return false }
            return buffer[(start + 8)..<(start + 24)].allSatisfy { $0 == 0 }
        default:
            return false
        }
    }

    private static func address(_ buffer: [UInt8], at start: Int, end: Int) -> String? {
        switch Int32(buffer[start + 1]) {
        case AF_INET:
            guard start + 8 <= end else { return nil }
            return buffer[(start + 4)..<(start + 8)].map(String.init).joined(separator: ".")
        case AF_INET6:
            guard start + 24 <= end else { return nil }
            var bytes = Array(buffer[(start + 8)..<(start + 24)])
            // The kernel stores the interface index inside a link-local
            // address (fe80:4::1). Clear it to show fe80::1.
            if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 {
                bytes[2] = 0
                bytes[3] = 0
            }
            var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let ok = bytes.withUnsafeBytes { raw in
                inet_ntop(AF_INET6, raw.baseAddress, &text, socklen_t(text.count)) != nil
            }
            return ok ? String(nulTerminated: text) : nil
        default:
            return nil
        }
    }
}

public enum RouteCollector {
    // Stable Darwin constants: CTL_NET, PF_ROUTE, NET_RT_DUMP.
    private static let ctlNet: Int32 = 4
    private static let pfRoute: Int32 = 17
    private static let netRtDump: Int32 = 1

    /// The default routes of IPv4 and IPv6.
    public static func defaultRoutes() -> [DefaultRoute] {
        defaultRoutes(family: AF_INET) + defaultRoutes(family: AF_INET6)
    }

    public static func defaultRoutes(family: Int32) -> [DefaultRoute] {
        var mib: [Int32] = [ctlNet, pfRoute, 0, family, netRtDump, 0]
        var needed = 0
        guard sysctl(&mib, 6, nil, &needed, nil, 0) == 0, needed > 0 else { return [] }

        // The table can grow between the two calls. Leave some room.
        needed += needed / 4
        var buffer = [UInt8](repeating: 0, count: needed)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return sysctl(&mib, 6, base, &needed, nil, 0) == 0
        }
        guard ok, needed > 0 else { return [] }

        return RouteMessageParser.defaultRoutes(
            in: Array(buffer[..<needed]),
            isIPv6: family == AF_INET6,
            interfaceName: interfaceName(index:))
    }

    private static func interfaceName(index: Int) -> String? {
        guard index > 0 else { return nil }
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(index), &name) != nil else { return nil }
        return String(nulTerminated: name)
    }
}
