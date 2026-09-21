import Foundation

/// Manufacturer names by MAC prefix (IEEE OUI registry).
///
/// The registry file has one entry per line: six hex digits, a tab, the name.
public struct OUIRegistry: Sendable {
    private let table: [String: String]

    public init(table: [String: String] = [:]) {
        self.table = table
    }

    public init(text: String) {
        var table: [String: String] = [:]
        table.reserveCapacity(40_000)
        for line in text.split(whereSeparator: \.isNewline) {
            guard let tab = line.firstIndex(of: "\t"),
                line.distance(from: line.startIndex, to: tab) == 6
            else { continue }
            table[line[..<tab].uppercased()] = String(line[line.index(after: tab)...])
        }
        self.table = table
    }

    public var count: Int { table.count }

    fileprivate func table(forPrefix prefix: String) -> String? { table[prefix] }

    /// The vendor of an end device, from the real prefix only. A random
    /// address has no vendor, and nothing is read into it.
    public func vendor(forMAC mac: String) -> String? {
        MACAddress.prefix(mac).flatMap { table[$0] }
    }

    /// The vendor of an access point.
    ///
    /// Access points do not randomize their BSSID. Those that broadcast several
    /// networks (guest Wi-Fi, mesh) do derive the extra BSSIDs from their own
    /// address and set the "locally administered" bit while doing so. Without
    /// that bit the prefix is the real one. With it, clearing the bit gives
    /// the base address.
    public func vendor(forBSSID bssid: String) -> String? {
        if let direct = vendor(forMAC: bssid) { return direct }
        guard let canonical = MACAddress.canonical(bssid),
            MACAddress.isLocallyAdministered(canonical),
            let firstByte = UInt8(canonical.prefix(2), radix: 16)
        else { return nil }
        let cleared = String(format: "%02X", firstByte & ~0x02)
        let rest = canonical.split(separator: ":").dropFirst().prefix(2).joined()
        return table[cleared + rest]
    }
}

/// What the OUI tool says about an address.
public enum OUIResult: Sendable, Equatable {
    case vendor(String)
    /// The "locally administered" bit is set: the address was not assigned by
    /// a manufacturer, so it has no vendor (typical for the private Wi-Fi
    /// address of iOS).
    case locallyAdministered
    case notFound
}

extension OUIRegistry {
    /// Looks up a MAC address or its first three bytes, in the spellings with
    /// `:`, `-`, `.`, spaces or none at all.
    public func lookup(_ input: String) throws -> OUIResult {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw InputError.empty }
        guard text.allSatisfy({ $0.isHexDigit || ":-. ".contains($0) }) else { throw InputError.invalidMAC }
        let digits = text.filter(\.isHexDigit).uppercased()
        guard digits.count == 6 || digits.count == 12,
            let firstByte = UInt8(digits.prefix(2), radix: 16)
        else { throw InputError.invalidMAC }
        if firstByte & 0x02 != 0 { return .locallyAdministered }
        if let vendor = table(forPrefix: String(digits.prefix(6))) { return .vendor(vendor) }
        return .notFound
    }
}
