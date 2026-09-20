public enum MACAddress {
    /// A MAC address as colon separated, upper case pairs, or `nil` if the
    /// input is not a MAC address.
    ///
    /// iOS drops leading zeros in a BSSID ("0:11:22:aa:bb:cc"), so the colon
    /// separated form is padded byte by byte. Other spellings ("0011.22aa.bbcc",
    /// "00-11-22-AA-BB-CC") are read as 12 hex digits.
    public static func canonical(_ mac: String) -> String? {
        let bytes: [String]
        let colonParts = mac.split(separator: ":", omittingEmptySubsequences: false)
        if colonParts.count == 6, colonParts.allSatisfy({ (1...2).contains($0.count) }) {
            bytes = colonParts.map { $0.count == 1 ? "0" + $0 : String($0) }
        } else {
            let hex = mac.filter(\.isHexDigit)
            guard hex.count == 12 else { return nil }
            bytes = stride(from: 0, to: 12, by: 2).map { index in
                let start = hex.index(hex.startIndex, offsetBy: index)
                return String(hex[start..<hex.index(start, offsetBy: 2)])
            }
        }
        let joined = bytes.joined(separator: ":").uppercased()
        return joined.filter(\.isHexDigit).count == 12 ? joined : nil
    }

    /// The first three bytes as six hex digits, for the vendor lookup.
    public static func prefix(_ mac: String) -> String? {
        guard let canonical = canonical(mac) else { return nil }
        return canonical.split(separator: ":").prefix(3).joined()
    }

    /// True if the "locally administered" bit is set. On devices that usually
    /// means a random address, such as the private Wi-Fi address of iOS.
    public static func isLocallyAdministered(_ mac: String) -> Bool {
        guard let canonical = canonical(mac),
            let firstByte = UInt8(canonical.prefix(2), radix: 16)
        else { return false }
        return firstByte & 0x02 != 0
    }
}
