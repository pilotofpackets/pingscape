import CryptoKit
import Darwin
import Foundation

/// Replaces the addresses and names in a snapshot, so a diagnostic dump can be
/// shared without giving away the network.
///
/// What a diagnosis needs stays intact: the address class (link-local,
/// private, shared, public, unique local), the prefix length and which
/// addresses share a network. A gateway stays inside the network of its
/// interface. The mapping is prefix preserving (the idea of Crypto-PAn): two
/// addresses that share their first *n* bits still share them afterwards.
/// The key is random for each dump, so the mapping cannot be reversed by
/// trying addresses.
public struct SnapshotAnonymizer {
    private let key: SymmetricKey
    private var cache: [String: String] = [:]

    public init(key: SymmetricKey = SymmetricKey(size: .bits256)) {
        self.key = key
    }

    public mutating func anonymize(_ snapshot: NetworkSnapshot) -> NetworkSnapshot {
        var result = snapshot
        result.interfaces = snapshot.interfaces.map { interface in
            NetworkInterface(
                name: interface.name, kind: interface.kind, isUp: interface.isUp, flags: interface.flags,
                mtu: interface.mtu,
                addresses: interface.addresses.map { address in
                    InterfaceAddress(
                        ip: ip(address.ip), isIPv6: address.isIPv6, prefixLength: address.prefixLength,
                        netmask: address.netmask)
                },
                receivedBytes: interface.receivedBytes, sentBytes: interface.sentBytes,
                receivedPackets: interface.receivedPackets, sentPackets: interface.sentPackets)
        }
        result.defaultRoutes = snapshot.defaultRoutes.map {
            DefaultRoute(
                interfaceName: $0.interfaceName, gateway: $0.gateway.map { ip($0) }, isIPv6: $0.isIPv6,
                isActive: $0.isActive)
        }
        result.dnsServers = snapshot.dnsServers.map { ip($0) }
        result.proxy = ProxyInfo(
            isEnabled: snapshot.proxy.isEnabled,
            host: snapshot.proxy.host.map { ToolInput.isIPv4($0) || ToolInput.isIPv6($0) ? ip($0) : "proxy.example" },
            port: snapshot.proxy.port,
            pacURL: snapshot.proxy.pacURL.map { _ in "https://proxy.example/proxy.pac" })
        if case .value(let wifi) = snapshot.wifi {
            result.wifi = .value(
                WiFiInfo(
                    ssid: "Network", bssid: wifi.bssid.map { mac($0) }, security: wifi.security,
                    didAutoJoin: wifi.didAutoJoin, didJustJoin: wifi.didJustJoin))
        }
        result.cellularServices = snapshot.cellularServices.enumerated().map { index, service in
            CellularService(id: "service-\(index + 1)", isDataService: service.isDataService, technology: service.technology)
        }
        if let path = snapshot.path {
            result.path = PathSummary(
                isOnline: path.isOnline, supportsIPv4: path.supportsIPv4, supportsIPv6: path.supportsIPv6,
                supportsDNS: path.supportsDNS, isExpensive: path.isExpensive, isConstrained: path.isConstrained,
                gateways: path.gateways.map { ip($0) }, unsatisfiedReason: path.unsatisfiedReason,
                cellularInterface: path.cellularInterface)
        }
        // External values are not part of a dump.
        result.publicIPv4 = .none
        result.publicIPv6 = .none
        return result
    }

    /// Any IPv4 or IPv6 address. Text that is no address is returned unchanged.
    public mutating func ip(_ text: String) -> String {
        if let cached = cache[text] { return cached }
        let mapped: String
        if var v4 = Optional(in_addr()), inet_pton(AF_INET, text, &v4) == 1 {
            mapped = mapV4(UInt32(bigEndian: v4.s_addr))
        } else if var v6 = Optional(in6_addr()), inet_pton(AF_INET6, text, &v6) == 1 {
            mapped = mapV6(withUnsafeBytes(of: &v6) { Array($0) })
        } else {
            mapped = text
        }
        cache[text] = mapped
        return mapped
    }

    /// A MAC address with its vendor prefix and its two flag bits kept.
    mutating func mac(_ text: String) -> String {
        guard let canonical = MACAddress.canonical(text) else { return text }
        var bytes = canonical.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { return text }
        for index in 3..<6 { bytes[index] ^= randomByte(label: "mac", position: index, bytes: Array(bytes.prefix(index))) }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    // MARK: Prefix preserving mapping

    /// A pseudo-random bit for a prefix. The same prefix always gives the same bit.
    private func bit(_ family: UInt8, _ length: Int, _ prefix: [UInt8], round: UInt8 = 0) -> UInt8 {
        var input = Data([family, UInt8(length), round])
        input.append(contentsOf: prefix)
        return Array(HMAC<SHA256>.authenticationCode(for: input, using: key)).first! & 1
    }

    private func randomByte(label: String, position: Int, bytes: [UInt8]) -> UInt8 {
        var input = Data(label.utf8)
        input.append(UInt8(position))
        input.append(contentsOf: bytes)
        return Array(HMAC<SHA256>.authenticationCode(for: input, using: key)).first!
    }

    /// Scrambles the bits from `fixed` on. Every output bit depends on the
    /// input bits before it, so shared prefixes stay shared.
    private func scramble(_ bytes: [UInt8], family: UInt8, fixed: Int, round: UInt8 = 0) -> [UInt8] {
        var output = bytes
        for index in fixed..<(bytes.count * 8) {
            // The prefix is the input's first `index` bits, padded with zeros.
            var prefix = [UInt8](repeating: 0, count: (index + 7) / 8)
            for position in 0..<index {
                let value = (bytes[position / 8] >> (7 - UInt8(position % 8))) & 1
                prefix[position / 8] |= value << (7 - UInt8(position % 8))
            }
            let flip = bit(family, index, prefix, round: round)
            output[index / 8] ^= flip << (7 - UInt8(index % 8))
        }
        return output
    }

    private func mapV4(_ value: UInt32) -> String {
        let octets = [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        // Kept whole: they say nothing about the network.
        if value == 0 || value == UInt32.max || octets[0] == 127 || octets[0] >= 224 {
            return octets.map(String.init).joined(separator: ".")
        }
        let fixed = Self.fixedBitsV4(octets)
        var round: UInt8 = 0
        var mapped = scramble(octets, family: 4, fixed: fixed, round: round)
        // A public address must not turn into a private, shared or reserved one.
        while fixed == 0, Self.isSpecialV4(mapped), round < 16 {
            round += 1
            mapped = scramble(octets, family: 4, fixed: fixed, round: round)
        }
        return mapped.map(String.init).joined(separator: ".")
    }

    /// How many leading bits give an address its class.
    private static func fixedBitsV4(_ octets: [UInt8]) -> Int {
        switch (octets[0], octets[1]) {
        case (10, _): 8
        case (172, 16...31): 12
        case (192, 168): 16
        case (169, 254): 16
        case (100, 64...127): 10
        default: 0
        }
    }

    private static func isSpecialV4(_ octets: [UInt8]) -> Bool {
        octets[0] == 0 || octets[0] == 127 || octets[0] >= 224 || fixedBitsV4(octets) != 0
            || (octets[0] == 192 && octets[1] == 0) || (octets[0] == 198 && (18...19).contains(octets[1]))
    }

    private func mapV6(_ bytes: [UInt8]) -> String {
        let isZero = bytes.allSatisfy { $0 == 0 }
        let isLoopback = bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] == 1
        guard !isZero, !isLoopback, bytes[0] != 0xFF else { return Self.text(v6: bytes) }
        let fixed: Int
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 {
            fixed = 64  // link-local: keep fe80::/64, scramble the interface identifier
        } else if bytes[0] & 0xFE == 0xFC {
            fixed = 8  // unique local: keep fc or fd
        } else {
            fixed = 3  // global unicast 2000::/3
        }
        return Self.text(v6: scramble(bytes, family: 6, fixed: fixed))
    }

    private static func text(v6 bytes: [UInt8]) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, bytes, &buffer, socklen_t(buffer.count)) != nil else { return "::" }
        return String(nulTerminated: buffer)
    }
}
