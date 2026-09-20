import Darwin

extension String {
    /// Text from a NUL-terminated C character buffer.
    init(nulTerminated buffer: [CChar]) {
        self = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// `sockaddr` helpers shared by the collectors.
enum SocketAddress {
    /// The numeric host of a `sockaddr`, without a zone suffix (`%en0`).
    static func numericHost(_ sa: UnsafePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(sa.pointee.sa_len)
        guard getnameinfo(sa, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
        else { return nil }
        let raw = String(nulTerminated: buffer)
        return raw.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }

    /// The number of set bits of a netmask, for IPv4 and IPv6.
    static func prefixLength(_ mask: UnsafePointer<sockaddr>) -> Int? {
        let family = Int32(mask.pointee.sa_family)
        var bytes: [UInt8]
        if family == AF_INET {
            bytes = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin_addr) { Array($0) }
            }
        } else if family == AF_INET6 {
            bytes = mask.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
            }
        } else {
            return nil
        }
        var count = 0
        for byte in bytes {
            if byte == 0xFF {
                count += 8
            } else {
                var value = byte
                while value & 0x80 != 0 {
                    count += 1
                    value <<= 1
                }
                break
            }
        }
        return count
    }
}
