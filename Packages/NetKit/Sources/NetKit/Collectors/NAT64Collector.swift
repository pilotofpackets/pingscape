import Darwin

/// Detects NAT64/DNS64, which IPv6-only mobile networks use.
///
/// `ipv4only.arpa` has only the IPv4 addresses 192.0.0.170 and 192.0.0.171. On
/// a NAT64 network the resolver synthesizes IPv6 addresses for them from the
/// network's prefix (`64:ff9b::/96` or a prefix of the operator). If an IPv6
/// address comes back, the prefix is that address without its last 32 bits.
public enum NAT64Collector {
    /// The /96 prefix, or `nil` if the network does not synthesize addresses.
    public static func prefix() -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET6
        hints.ai_socktype = SOCK_STREAM
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo("ipv4only.arpa", nil, &hints, &info) == 0, let first = info else { return nil }
        defer { freeaddrinfo(info) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ai_next }
            guard entry.pointee.ai_family == AF_INET6, let sa = entry.pointee.ai_addr else { continue }
            let bytes = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
            }
            if let prefix = prefix(fromSynthesized: bytes) { return prefix }
        }
        return nil
    }

    /// The prefix of a synthesized address, or `nil` if its last four bytes are
    /// not one of the two addresses of `ipv4only.arpa`.
    static func prefix(fromSynthesized bytes: [UInt8]) -> String? {
        guard bytes.count == 16, Array(bytes[12...14]) == [192, 0, 0], bytes[15] == 170 || bytes[15] == 171 else {
            return nil
        }
        var network = bytes
        for index in 12..<16 { network[index] = 0 }
        var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, network, &text, socklen_t(text.count)) != nil else { return nil }
        return String(nulTerminated: text) + "/96"
    }
}
