import Darwin
import Foundation

public enum DNSRecordType: String, CaseIterable, Sendable {
    case a = "A"
    case aaaa = "AAAA"
    case cname = "CNAME"
    case mx = "MX"
    case ns = "NS"
    case txt = "TXT"
    case soa = "SOA"
    case ptr = "PTR"
    case srv = "SRV"
    case caa = "CAA"
    case any = "ANY"

    var code: UInt16 {
        switch self {
        case .a: 1
        case .ns: 2
        case .cname: 5
        case .soa: 6
        case .ptr: 12
        case .mx: 15
        case .txt: 16
        case .aaaa: 28
        case .srv: 33
        case .caa: 257
        case .any: 255
        }
    }

    /// The name of a type code as it appears in an answer.
    static func label(forCode code: UInt16) -> String {
        allCases.first { $0.code == code }?.rawValue ?? "TYPE\(code)"
    }
}

public struct DNSRecord: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let name: String
    public let type: String
    public let ttl: UInt32
    public let value: String

    public init(name: String, type: String, ttl: UInt32, value: String) {
        self.name = name
        self.type = type
        self.ttl = ttl
        self.value = value
    }

    public static func == (lhs: DNSRecord, rhs: DNSRecord) -> Bool {
        lhs.name == rhs.name && lhs.type == rhs.type && lhs.ttl == rhs.ttl && lhs.value == rhs.value
    }
}

public enum DNSError: Error, Sendable, Equatable {
    /// The reply is not a DNS message.
    case malformed
    case invalidName
}

/// The parts of a reply the tool needs.
struct DNSParsedMessage: Sendable, Equatable {
    var identifier: UInt16
    var flags: UInt16
    var responseCode: Int
    var answers: [DNSRecord]
    /// The reply claims more records than the packet holds.
    var isIncomplete: Bool
    /// The reply carries an EDNS OPT record.
    var hasEDNS: Bool

    var isTruncated: Bool { flags & 0x0200 != 0 }
}

/// DNS wire format (RFC 1035), with EDNS0 (RFC 6891).
enum DNSMessage {
    /// The UDP size offered through EDNS. 1232 bytes is the value from DNS
    /// Flag Day 2020: it passes without fragmentation almost everywhere.
    static let ednsUDPSize: UInt16 = 1232

    static func encodeName(_ name: String) throws -> [UInt8] {
        var bytes: [UInt8] = []
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        if !trimmed.isEmpty {
            for label in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
                let utf8 = Array(label.utf8)
                guard (1...63).contains(utf8.count) else { throw DNSError.invalidName }
                bytes.append(UInt8(utf8.count))
                bytes += utf8
            }
        }
        bytes.append(0)
        guard bytes.count <= 255 else { throw DNSError.invalidName }
        return bytes
    }

    static func query(
        id: UInt16, name: String, type: DNSRecordType, recursionDesired: Bool = true, ednsUDPSize: UInt16? = nil
    ) throws -> [UInt8] {
        var packet: [UInt8] = []
        func append16(_ value: UInt16) { packet += [UInt8(value >> 8), UInt8(value & 0xFF)] }
        append16(id)
        append16(recursionDesired ? 0x0100 : 0)
        append16(1)
        append16(0)
        append16(0)
        append16(ednsUDPSize == nil ? 0 : 1)
        packet += try encodeName(name)
        append16(type.code)
        append16(1)  // class IN
        if let ednsUDPSize {
            packet.append(0)  // root name
            append16(41)  // OPT
            append16(ednsUDPSize)
            packet += [0, 0, 0, 0]  // extended rcode, version, flags
            append16(0)  // no options
        }
        return packet
    }

    /// The name to ask for a reverse lookup of an address.
    static func reverseName(of ip: String) -> String? {
        guard let address = ResolvedAddress(literal: ip) else { return nil }
        if !address.isIPv6 {
            return ip.split(separator: ".").reversed().joined(separator: ".") + ".in-addr.arpa"
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, ip, &v6) == 1 else { return nil }
        let nibbles = withUnsafeBytes(of: &v6) { raw in
            raw.flatMap { byte in [String(byte >> 4, radix: 16), String(byte & 0xF, radix: 16)] }
        }
        return nibbles.reversed().joined(separator: ".") + ".ip6.arpa"
    }

    // MARK: Reading

    static func parse(_ data: [UInt8]) throws -> DNSParsedMessage {
        guard data.count >= 12 else { throw DNSError.malformed }
        func u16(_ offset: Int) -> Int { Int(data[offset]) << 8 | Int(data[offset + 1]) }
        let flags = UInt16(u16(2))
        let questions = u16(4)
        let answerCount = u16(6)
        let extraCount = u16(8) + u16(10)

        var message = DNSParsedMessage(
            identifier: UInt16(u16(0)), flags: flags, responseCode: Int(flags & 0xF), answers: [],
            isIncomplete: false, hasEDNS: false)
        var offset = 12
        do {
            for _ in 0..<questions {
                offset = try skipName(data, offset) + 4
                guard offset <= data.count else { throw DNSError.malformed }
            }
            for _ in 0..<answerCount {
                let (record, next) = try readRecord(data, offset)
                if let record { message.answers.append(record) }
                offset = next
            }
            for _ in 0..<extraCount {
                let end = try skipName(data, offset)
                guard end + 10 <= data.count else { throw DNSError.malformed }
                if u16(end) == 41 { message.hasEDNS = true }
                offset = end + 10 + u16(end + 8)
                guard offset <= data.count else { throw DNSError.malformed }
            }
        } catch {
            // The header was fine, the rest is cut off.
            message.isIncomplete = true
        }
        return message
    }

    /// The offset after the name that starts at `offset`.
    private static func skipName(_ data: [UInt8], _ offset: Int) throws -> Int {
        var position = offset
        while true {
            guard position < data.count else { throw DNSError.malformed }
            let length = Int(data[position])
            if length == 0 { return position + 1 }
            if length & 0xC0 == 0xC0 { return position + 2 }
            position += 1 + length
        }
    }

    /// A name, following compression pointers. Returns the text and the
    /// offset after the name at its original place.
    static func readName(_ data: [UInt8], _ start: Int) throws -> (name: String, next: Int) {
        var labels: [String] = []
        var position = start
        var next: Int?
        var jumps = 0
        var total = 0
        while true {
            guard position < data.count else { throw DNSError.malformed }
            let length = Int(data[position])
            if length == 0 {
                position += 1
                break
            }
            if length & 0xC0 == 0xC0 {
                guard position + 1 < data.count else { throw DNSError.malformed }
                let target = (length & 0x3F) << 8 | Int(data[position + 1])
                if next == nil { next = position + 2 }
                jumps += 1
                // A pointer must go back, and a loop must end.
                guard jumps <= 64, target < position else { throw DNSError.malformed }
                position = target
                continue
            }
            guard length & 0xC0 == 0, position + 1 + length <= data.count else { throw DNSError.malformed }
            total += length + 1
            guard total <= 255 else { throw DNSError.malformed }
            labels.append(escape(Array(data[(position + 1)..<(position + 1 + length)])))
            position += 1 + length
        }
        return (labels.isEmpty ? "." : labels.joined(separator: "."), next ?? position)
    }

    /// A label as text. Bytes that are not printable, and dots inside a label,
    /// are written as `\DDD` (RFC 4343), so nothing is lost or invented.
    private static func escape(_ bytes: [UInt8]) -> String {
        var text = ""
        for byte in bytes {
            if byte == 0x2E || byte == 0x5C {
                text += "\\" + String(UnicodeScalar(byte))
            } else if byte >= 0x21 && byte <= 0x7E {
                text += String(UnicodeScalar(byte))
            } else {
                text += "\\" + String(format: "%03d", byte)
            }
        }
        return text
    }

    private static func readRecord(_ data: [UInt8], _ offset: Int) throws -> (DNSRecord?, Int) {
        let (name, afterName) = try readName(data, offset)
        guard afterName + 10 <= data.count else { throw DNSError.malformed }
        func u16(_ at: Int) -> Int { Int(data[at]) << 8 | Int(data[at + 1]) }
        let type = UInt16(u16(afterName))
        let ttl = UInt32(u16(afterName + 4)) << 16 | UInt32(u16(afterName + 6))
        let length = u16(afterName + 8)
        let start = afterName + 10
        guard start + length <= data.count else { throw DNSError.malformed }
        let record = DNSRecord(
            name: name, type: DNSRecordType.label(forCode: type), ttl: ttl,
            value: try readData(data, type: type, start: start, length: length))
        return (record, start + length)
    }

    private static func readData(_ data: [UInt8], type: UInt16, start: Int, length: Int) throws -> String {
        let end = start + length
        func u16(_ at: Int) throws -> Int {
            guard at + 2 <= end else { throw DNSError.malformed }
            return Int(data[at]) << 8 | Int(data[at + 1])
        }
        func u32(_ at: Int) throws -> UInt32 {
            guard at + 4 <= end else { throw DNSError.malformed }
            return UInt32(try u16(at)) << 16 | UInt32(try u16(at + 2))
        }
        switch type {
        case 1:
            guard length == 4 else { throw DNSError.malformed }
            return data[start..<end].map(String.init).joined(separator: ".")
        case 28:
            guard length == 16 else { throw DNSError.malformed }
            var address = in6_addr()
            withUnsafeMutableBytes(of: &address) { $0.copyBytes(from: data[start..<end]) }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else {
                throw DNSError.malformed
            }
            return String(nulTerminated: buffer)
        case 2, 5, 12:
            return try readName(data, start).name
        case 15:
            return "\(try u16(start)) \(try readName(data, start + 2).name)"
        case 6:
            let (primary, afterPrimary) = try readName(data, start)
            let (mailbox, afterMailbox) = try readName(data, afterPrimary)
            let numbers = try (0..<5).map { try u32(afterMailbox + $0 * 4) }
            return ([primary, mailbox] + numbers.map(String.init)).joined(separator: " ")
        case 33:
            let target = try readName(data, start + 6).name
            return "\(try u16(start)) \(try u16(start + 2)) \(try u16(start + 4)) \(target)"
        case 16:
            var strings: [String] = []
            var position = start
            while position < end {
                let size = Int(data[position])
                guard position + 1 + size <= end else { throw DNSError.malformed }
                strings.append(quote(Array(data[(position + 1)..<(position + 1 + size)])))
                position += 1 + size
            }
            return strings.joined(separator: " ")
        case 257:
            guard length >= 2 else { throw DNSError.malformed }
            let tagLength = Int(data[start + 1])
            guard start + 2 + tagLength <= end else { throw DNSError.malformed }
            let tag = String(decoding: data[(start + 2)..<(start + 2 + tagLength)], as: UTF8.self)
            let value = quote(Array(data[(start + 2 + tagLength)..<end]))
            return "\(data[start]) \(tag) \(value)"
        default:
            // Unknown type: the data as RFC 3597 writes it.
            return "\\# \(length) " + data[start..<end].map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func quote(_ bytes: [UInt8]) -> String {
        var text = "\""
        for byte in bytes {
            switch byte {
            case 0x22: text += "\\\""
            case 0x5C: text += "\\\\"
            case 0x20...0x7E: text += String(UnicodeScalar(byte))
            default: text += "\\" + String(format: "%03d", byte)
            }
        }
        return text + "\""
    }
}
