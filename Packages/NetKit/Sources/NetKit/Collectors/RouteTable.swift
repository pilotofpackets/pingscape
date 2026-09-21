import Darwin

/// One entry of the routing table.
public struct RouteEntry: Sendable, Hashable, Codable, Identifiable {
    public var id: String { "\(isIPv6 ? 6 : 4)|\(destination)|\(prefixLength ?? -1)|\(interfaceName)|\(gateway ?? "")|\(flags)" }

    /// The destination address, or `default`.
    public let destination: String
    /// The prefix length. `nil` for a default route and for entries without a mask.
    public let prefixLength: Int?
    public let gateway: String?
    public let interfaceName: String
    /// The route flags as letters, the way `netstat -rn` writes them (`UGSI`).
    public let flags: String
    public let isIPv6: Bool

    public init(
        destination: String, prefixLength: Int?, gateway: String?, interfaceName: String, flags: String,
        isIPv6: Bool
    ) {
        self.destination = destination
        self.prefixLength = prefixLength
        self.gateway = gateway
        self.interfaceName = interfaceName
        self.flags = flags
        self.isIPv6 = isIPv6
    }

    public var isDefault: Bool { destination == "default" }

    /// `192.0.2.0/24`, or just the address for a host route.
    public var destinationWithPrefix: String {
        prefixLength.map { "\(destination)/\($0)" } ?? destination
    }
}

extension RouteMessageParser {
    /// The letters `netstat -rn` uses for the flags that matter here.
    private static let flagLetters: [(Int32, Character)] = [
        (0x1, "U"), (0x2, "G"), (0x4, "H"), (0x8, "R"), (0x10, "D"), (0x20, "M"), (0x400, "L"),
        (0x800, "S"), (0x1000, "B"), (0x20000, "W"), (0x100_0000, "I"),
    ]

    static func flagString(_ flags: Int32) -> String {
        String(flagLetters.filter { flags & $0.0 != 0 }.map(\.1))
    }

    /// Every IPv4 or IPv6 route of a table dump, in the order of the table.
    public static func routes(
        in buffer: [UInt8], isIPv6: Bool, interfaceName: (Int) -> String?
    ) -> [RouteEntry] {
        func u16(_ offset: Int) -> Int { Int(buffer[offset]) | (Int(buffer[offset + 1]) << 8) }
        func i32(_ offset: Int) -> Int32 {
            var value: UInt32 = 0
            for byte in 0..<4 { value |= UInt32(buffer[offset + byte]) << (8 * UInt32(byte)) }
            return Int32(bitPattern: value)
        }

        var entries: [RouteEntry] = []
        var offset = 0
        while offset + headerSize <= buffer.count {
            let length = u16(offset)
            if length < headerSize || offset + length > buffer.count { break }
            defer { offset += length }

            let index = u16(offset + 4)
            let flags = i32(offset + 8)
            let addrs = i32(offset + 12)
            guard addrs & addrDestination != 0, let name = interfaceName(index) else { continue }

            var cursor = offset + headerSize
            let end = offset + length
            var destination: String?
            var isDefault = false
            var gateway: String?
            var maskBytes: [UInt8]?
            var maskLength = 0

            // Destination is bit 0, gateway bit 1, netmask bit 2.
            for bit in 0..<3 {
                guard addrs & (1 << Int32(bit)) != 0 else { continue }
                guard cursor + 1 < end else { break }
                let saLength = Int(buffer[cursor])
                let saEnd = min(cursor + saLength, end)
                switch bit {
                case 0:
                    isDefault = isUnspecifiedAddress(buffer, at: cursor, end: end)
                    destination = ipAddress(buffer, at: cursor, end: end)
                case 1:
                    if flags & flagGateway != 0 { gateway = ipAddress(buffer, at: cursor, end: end) }
                default:
                    // The kernel drops trailing zero bytes of a mask, so its
                    // length varies. The address bytes start after the header of
                    // the sockaddr (4 bytes for IPv4, 8 for IPv6).
                    let start = cursor + (isIPv6 ? 8 : 4)
                    maskBytes = start < saEnd ? Array(buffer[start..<saEnd]) : []
                    maskLength = isIPv6 ? 16 : 4
                }
                cursor += saLength > 0 ? (saLength + 3) & ~3 : 4
            }

            guard isDefault || destination != nil else { continue }
            var prefix: Int?
            if isDefault {
                prefix = nil
            } else if flags & flagHost != 0 {
                prefix = isIPv6 ? 128 : 32
            } else if let maskBytes {
                prefix = maskBytes.prefix(maskLength).reduce(into: (count: 0, done: false)) { state, byte in
                    guard !state.done else { return }
                    if byte == 0xFF {
                        state.count += 8
                    } else {
                        var value = byte
                        while value & 0x80 != 0 {
                            state.count += 1
                            value <<= 1
                        }
                        state.done = true
                    }
                }.count
            }
            entries.append(
                RouteEntry(
                    destination: isDefault ? "default" : destination ?? "",
                    prefixLength: prefix,
                    gateway: (gateway?.isEmpty ?? true) ? nil : gateway,
                    interfaceName: name, flags: flagString(flags), isIPv6: isIPv6))
        }
        return entries
    }
}

extension RouteCollector {
    /// The whole routing table, IPv4 then IPv6. Empty if the system does not answer.
    public static func allRoutes() -> [RouteEntry] {
        allRoutes(family: AF_INET) + allRoutes(family: AF_INET6)
    }
}
