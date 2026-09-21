import Foundation

/// What a Whois or RDAP lookup is about.
public enum LookupTarget: Sendable, Equatable {
    case domain(String)
    case ip(String)
    /// An autonomous system number.
    case asn(UInt32)

    /// Reads a domain, an IP address or an AS number (`AS64500` or `64500`).
    public init(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InputError.empty }
        let digits = trimmed.lowercased().hasPrefix("as") ? String(trimmed.dropFirst(2)) : trimmed
        if !digits.isEmpty, digits.allSatisfy(\.isNumber), let number = UInt32(digits) {
            self = .asn(number)
            return
        }
        let host = try ToolInput.host(trimmed)
        self = ToolInput.isIPv4(host) || ToolInput.isIPv6(host) ? .ip(host) : .domain(host)
    }

    /// The text a Whois server takes.
    var whoisQuery: String {
        switch self {
        case .domain(let name): name
        case .ip(let address): address
        case .asn(let number): "AS\(number)"
        }
    }
}
