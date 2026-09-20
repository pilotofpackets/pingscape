/// Dotted-quad helpers.
public enum IPv4 {
    public static func toInt(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    public static func toString(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    /// The prefix length of a netmask, or `nil` if it is not a valid netmask.
    public static func prefix(fromNetmask netmask: String) -> Int? {
        guard let value = toInt(netmask) else { return nil }
        let ones = value.nonzeroBitCount
        // A valid mask is a run of ones followed by zeros.
        let expected: UInt32 = ones == 0 ? 0 : ~UInt32(0) << UInt32(32 - ones)
        return value == expected ? ones : nil
    }

    public static func netmask(fromPrefix prefix: Int) -> String {
        if prefix <= 0 { return "0.0.0.0" }
        if prefix >= 32 { return "255.255.255.255" }
        return toString(~UInt32(0) << UInt32(32 - prefix))
    }
}

/// An IPv4 network such as 192.168.178.0/24.
public struct IPv4Range: Sendable, Hashable {
    public let network: UInt32
    public let prefix: Int

    /// The address may be any host address of the network.
    public init?(ip: String, prefix: Int) {
        guard let value = IPv4.toInt(ip) else { return nil }
        let clamped = min(max(prefix, 1), 32)
        let mask: UInt32 = clamped >= 32 ? ~0 : ~UInt32(0) << UInt32(32 - clamped)
        self.network = value & mask
        self.prefix = clamped
    }

    public var networkAddress: String { IPv4.toString(network) }

    public var broadcast: String {
        let hostBits: UInt32 = prefix >= 32 ? 0 : ~UInt32(0) >> UInt32(prefix)
        return IPv4.toString(network | hostBits)
    }

    /// Usable host addresses, without network and broadcast address.
    public var hostCount: Int {
        prefix >= 31 ? 1 : (1 << (32 - prefix)) - 2
    }

    /// The host addresses, capped so a large network cannot flood the sweep.
    public func hosts(limit: Int = 1024) -> [String] {
        if prefix >= 31 { return [IPv4.toString(network)] }
        let count = min(hostCount, limit)
        return (0..<count).map { IPv4.toString(network + 1 + UInt32($0)) }
    }

    public var description: String { "\(networkAddress)/\(prefix)" }
}
