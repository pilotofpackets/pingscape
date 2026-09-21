import Darwin
import Foundation

/// Why what the user typed cannot be used. The app turns each case into one
/// short sentence.
public enum InputError: Error, Sendable, Equatable {
    case empty
    case invalidHost
    case invalidPort
    case invalidPortList
    case tooManyPorts
    case invalidURL
    case invalidSubnet
    case invalidMAC
}

/// Reads what people type into the tool fields.
public enum ToolInput {
    /// A host name or IP address from free text.
    ///
    /// A scheme, credentials, port, path, query and a trailing dot are dropped,
    /// so a pasted URL works. International names become Punycode, which is what
    /// goes on the wire. Underscores are allowed only for DNS names such as
    /// `_sip._tcp.example.com`.
    public static func host(_ text: String, allowUnderscore: Bool = false) throws -> String {
        try hostAndPort(text, defaultPort: nil, allowUnderscore: allowUnderscore).host
    }

    /// `host`, `host:port` or `[ipv6]:port`. The port is `defaultPort` if absent.
    public static func hostAndPort(
        _ text: String, defaultPort: UInt16?, allowUnderscore: Bool = false
    ) throws -> (host: String, port: UInt16?) {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { throw InputError.empty }
        if let scheme = rest.range(of: "://") { rest = String(rest[scheme.upperBound...]) }
        if let end = rest.firstIndex(where: { "/?#".contains($0) }) { rest = String(rest[..<end]) }
        if let at = rest.lastIndex(of: "@") { rest = String(rest[rest.index(after: at)...]) }

        var host = rest
        var port = defaultPort
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { throw InputError.invalidHost }
            host = String(rest[rest.index(after: rest.startIndex)..<close])
            let after = rest[rest.index(after: close)...]
            if !after.isEmpty {
                guard after.hasPrefix(":"), let value = UInt16(after.dropFirst()), value > 0 else {
                    throw InputError.invalidPort
                }
                port = value
            }
        } else if rest.filter({ $0 == ":" }).count == 1, let colon = rest.firstIndex(of: ":") {
            host = String(rest[..<colon])
            guard let value = UInt16(rest[rest.index(after: colon)...]), value > 0 else {
                throw InputError.invalidPort
            }
            port = value
        }

        if let zone = host.firstIndex(of: "%") { host = String(host[..<zone]) }
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { throw InputError.empty }
        if isIPv4(host) || isIPv6(host) { return (host, port) }
        return (try hostName(host, allowUnderscore: allowUnderscore), port)
    }

    /// True for a dotted-quad IPv4 address.
    public static func isIPv4(_ text: String) -> Bool {
        var address = in_addr()
        return inet_pton(AF_INET, text, &address) == 1
    }

    public static func isIPv6(_ text: String) -> Bool {
        var address = in6_addr()
        return inet_pton(AF_INET6, text, &address) == 1
    }

    private static func hostName(_ name: String, allowUnderscore: Bool) throws -> String {
        var ascii = name
        if !name.allSatisfy(\.isASCII) {
            guard let encoded = URLComponents(string: "https://" + name)?.encodedHost else {
                throw InputError.invalidHost
            }
            ascii = encoded
        }
        ascii = ascii.lowercased()
        guard ascii.utf8.count <= 253 else { throw InputError.invalidHost }
        let labels = ascii.split(separator: ".", omittingEmptySubsequences: false)
        for label in labels {
            guard (1...63).contains(label.utf8.count),
                !label.hasPrefix("-"), !label.hasSuffix("-"),
                label.allSatisfy({ character in
                    character.isASCII
                        && (character.isLetter || character.isNumber || character == "-"
                            || (allowUnderscore && character == "_"))
                })
            else { throw InputError.invalidHost }
        }
        // "1.2.3" or "999.1.1.1" are not host names, they are broken addresses.
        if labels.last.map({ $0.allSatisfy(\.isNumber) }) == true { throw InputError.invalidHost }
        return ascii
    }
}

/// Port lists such as `22,80,8000-8100`.
public enum PortList {
    /// The most this app scans in one run.
    public static let limit = 5000

    /// A sorted list without duplicates. Ranges count fully against the limit.
    public static func parse(_ text: String) throws -> [Int] {
        var ports = Set<Int>()
        let parts = text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        guard !parts.isEmpty else { throw InputError.invalidPortList }
        for part in parts {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
            guard bounds.count <= 2, let first = Int(bounds[0]), (1...65535).contains(first) else {
                throw InputError.invalidPortList
            }
            if bounds.count == 2 {
                guard let last = Int(bounds[1]), (1...65535).contains(last) else {
                    throw InputError.invalidPortList
                }
                let range = min(first, last)...max(first, last)
                guard range.count <= limit else { throw InputError.tooManyPorts }
                ports.formUnion(range)
            } else {
                ports.insert(first)
            }
            guard ports.count <= limit else { throw InputError.tooManyPorts }
        }
        return ports.sorted()
    }
}
