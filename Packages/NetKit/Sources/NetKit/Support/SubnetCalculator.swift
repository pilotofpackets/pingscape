import Foundation

/// The numbers of an IPv4 network, for the subnet calculator.
public struct SubnetInfo: Sendable, Equatable {
    public let address: String
    public let prefix: Int
    public let network: String
    public let mask: String
    public let wildcard: String
    /// `nil` for /31 and /32, which have no broadcast address.
    public let broadcast: String?
    public let firstHost: String
    public let lastHost: String
    public let hostCount: UInt64

    /// `192.0.2.42/24`, `192.0.2.42 255.255.255.0` or `192.0.2.42/255.255.255.0`.
    public init(_ text: String) throws {
        let parts = text.split(whereSeparator: { $0 == "/" || $0.isWhitespace }).map(String.init)
        guard parts.count == 2, let value = IPv4.toInt(parts[0]) else { throw InputError.invalidSubnet }
        let prefix: Int
        if let number = Int(parts[1]) {
            prefix = number
        } else if let fromMask = IPv4.prefix(fromNetmask: parts[1]) {
            prefix = fromMask
        } else {
            throw InputError.invalidSubnet
        }
        guard (0...32).contains(prefix) else { throw InputError.invalidSubnet }

        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << UInt32(32 - prefix)
        let network = value & mask
        let last = network | ~mask
        self.address = parts[0]
        self.prefix = prefix
        self.network = IPv4.toString(network)
        self.mask = IPv4.toString(mask)
        self.wildcard = IPv4.toString(~mask)
        switch prefix {
        case 32:
            broadcast = nil
            firstHost = self.network
            lastHost = self.network
            hostCount = 1
        case 31:
            // RFC 3021: both addresses are hosts, there is no broadcast.
            broadcast = nil
            firstHost = self.network
            lastHost = IPv4.toString(last)
            hostCount = 2
        default:
            broadcast = IPv4.toString(last)
            firstHost = IPv4.toString(network + 1)
            lastHost = IPv4.toString(last - 1)
            hostCount = (UInt64(1) << UInt64(32 - prefix)) - 2
        }
    }
}
