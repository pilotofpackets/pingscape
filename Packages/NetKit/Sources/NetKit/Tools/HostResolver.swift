import Darwin
import Foundation

/// A resolved IP address, ready for a socket.
public struct ResolvedAddress: Sendable, Hashable {
    /// Numeric text, without a zone suffix.
    public let text: String
    public let isIPv6: Bool
    /// The `sockaddr` bytes. The port is patched in by `socketBytes(port:)`.
    let storage: [UInt8]

    init(text: String, isIPv6: Bool, storage: [UInt8]) {
        self.text = text
        self.isIPv6 = isIPv6
        self.storage = storage
    }

    var family: Int32 { isIPv6 ? AF_INET6 : AF_INET }

    /// The address with a port, for `connect` and `sendto`.
    func socketBytes(port: UInt16) -> [UInt8] {
        var bytes = storage
        // `sin_port` and `sin6_port` both sit at byte 2, in network order.
        bytes[2] = UInt8(port >> 8)
        bytes[3] = UInt8(port & 0xFF)
        return bytes
    }

    func withSockaddr<T>(port: UInt16 = 0, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        let bytes = socketBytes(port: port)
        return bytes.withUnsafeBytes { raw in
            body(raw.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(bytes.count))
        }
    }

    /// An address from numeric text, or `nil` if the text is no IP address.
    public init?(literal: String) {
        let ip = literal.split(separator: "%", maxSplits: 1).first.map(String.init) ?? literal
        var v4 = sockaddr_in()
        v4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        v4.sin_family = sa_family_t(AF_INET)
        if inet_pton(AF_INET, ip, &v4.sin_addr) == 1 {
            self.init(
                text: ip, isIPv6: false,
                storage: withUnsafeBytes(of: &v4) { Array($0) })
            return
        }
        var v6 = sockaddr_in6()
        v6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        v6.sin6_family = sa_family_t(AF_INET6)
        if inet_pton(AF_INET6, ip, &v6.sin6_addr) == 1 {
            self.init(
                text: ip, isIPv6: true,
                storage: withUnsafeBytes(of: &v6) { Array($0) })
            return
        }
        return nil
    }
}

/// Turns names into addresses and addresses into names, with the system
/// resolver (so it follows the DNS servers of the current network or VPN).
public enum HostResolver {
    /// All addresses of a host in the order the system prefers them (IPv6
    /// first where it is usable, as `getaddrinfo` sorts). Blocks, so call it
    /// from `resolve(_:)`.
    static func resolveNow(_ host: String) -> [ResolvedAddress] {
        if let literal = ResolvedAddress(literal: host) { return [literal] }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &info) == 0, let first = info else { return [] }
        defer { freeaddrinfo(info) }

        var result: [ResolvedAddress] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ai_next }
            guard let sa = entry.pointee.ai_addr,
                entry.pointee.ai_family == AF_INET || entry.pointee.ai_family == AF_INET6,
                let text = SocketAddress.numericHost(sa)
            else { continue }
            let bytes = Array(UnsafeRawBufferPointer(start: sa, count: Int(entry.pointee.ai_addrlen)))
            let address = ResolvedAddress(
                text: text, isIPv6: entry.pointee.ai_family == AF_INET6, storage: bytes)
            if !result.contains(where: { $0.text == address.text }) { result.append(address) }
        }
        return result
    }

    /// All addresses of a host, or an empty list if the name does not resolve.
    public static func resolve(_ host: String) async throws -> [ResolvedAddress] {
        try await Blocking.run { _ in resolveNow(host) }
    }

    /// The name a reverse lookup gives for an address, or `nil` if there is none.
    public static func reverseName(of ip: String) async -> String? {
        try? await Blocking.run(qos: .utility) { _ in reverseNameNow(ip) }
    }

    static func reverseNameNow(_ ip: String) -> String? {
        guard let address = ResolvedAddress(literal: ip) else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = address.withSockaddr { sa, length in
            getnameinfo(sa, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NAMEREQD)
        }
        guard status == 0 else { return nil }
        let name = String(nulTerminated: buffer)
        // Some resolvers answer with the address itself.
        return name.isEmpty || name == ip ? nil : name
    }
}

extension ResolvedAddress {
    /// Whether the address is on this device's own side of the internet: private
    /// (RFC 1918), shared (100.64.0.0/10), link-local, loopback or unique local.
    /// Scanning such a target needs no warning, and reaching it needs the Local
    /// Network permission.
    public var isLocal: Bool {
        if !isIPv6 {
            let a = storage[4], b = storage[5]
            return a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
                || (a == 169 && b == 254) || (a == 100 && (64...127).contains(b))
        }
        let bytes = storage[8..<24]
        let first = bytes[bytes.startIndex], second = bytes[bytes.startIndex + 1]
        let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
        return isLoopback || first & 0xFE == 0xFC || (first == 0xFE && second & 0xC0 == 0x80)
    }
}
