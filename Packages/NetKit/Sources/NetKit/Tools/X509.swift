import Darwin
import Foundation

/// The parts of a certificate the TLS tool shows.
public struct CertificateInfo: Sendable, Equatable, Identifiable {
    public var id: String { serialNumber + (subjectName ?? "") + String(notAfter.timeIntervalSince1970) }

    public let subjectName: String?
    public let subjectOrganization: String?
    public let issuerName: String?
    public let issuerOrganization: String?
    public let notBefore: Date
    public let notAfter: Date
    /// Hexadecimal with colons, as browsers show it.
    public let serialNumber: String
    /// DNS names and IP addresses from the subject alternative names.
    public let alternativeNames: [String]

    public init(
        subjectName: String?, subjectOrganization: String?, issuerName: String?, issuerOrganization: String?,
        notBefore: Date, notAfter: Date, serialNumber: String, alternativeNames: [String]
    ) {
        self.subjectName = subjectName
        self.subjectOrganization = subjectOrganization
        self.issuerName = issuerName
        self.issuerOrganization = issuerOrganization
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.serialNumber = serialNumber
        self.alternativeNames = alternativeNames
    }

    /// Whole days from `now` to the end of validity. Negative once expired.
    public func daysUntilExpiry(from now: Date = Date()) -> Int {
        Int((notAfter.timeIntervalSince(now) / 86_400).rounded(.down))
    }

    /// Whether issuer and subject are the same name: a root or a self-signed certificate.
    public var isSelfIssued: Bool {
        subjectName == issuerName && subjectOrganization == issuerOrganization
    }
}

/// A small reader for the DER encoding of X.509 certificates (RFC 5280).
///
/// iOS has no public call that returns validity, issuer and alternative names
/// of a certificate (`SecCertificateCopyValues` exists only on the Mac), so
/// this reads them itself. It reads only, verifies nothing: whether a chain is
/// trusted is the system's answer (`SecTrust`).
public enum X509 {
    private struct Element {
        let tag: UInt8
        let content: ArraySlice<UInt8>
    }

    /// Reads TLV elements one after the other from a byte range.
    private struct Reader {
        let bytes: ArraySlice<UInt8>
        var position: Int

        init(_ bytes: ArraySlice<UInt8>) {
            self.bytes = bytes
            self.position = bytes.startIndex
        }

        var isAtEnd: Bool { position >= bytes.endIndex }

        mutating func next() -> Element? {
            guard position + 2 <= bytes.endIndex else { return nil }
            let tag = bytes[position]
            var length = Int(bytes[position + 1])
            var cursor = position + 2
            if length & 0x80 != 0 {
                let count = length & 0x7F
                guard count > 0, count <= 4, cursor + count <= bytes.endIndex else { return nil }
                length = 0
                for _ in 0..<count {
                    length = length << 8 | Int(bytes[cursor])
                    cursor += 1
                }
            }
            guard cursor + length <= bytes.endIndex else { return nil }
            position = cursor + length
            return Element(tag: tag, content: bytes[cursor..<(cursor + length)])
        }
    }

    // Object identifiers, as their DER content bytes.
    private static let commonName: [UInt8] = [0x55, 0x04, 0x03]
    private static let organization: [UInt8] = [0x55, 0x04, 0x0A]
    private static let subjectAltName: [UInt8] = [0x55, 0x1D, 0x11]

    public static func parse(der: [UInt8]) -> CertificateInfo? {
        var top = Reader(der[...])
        guard let certificate = top.next(), certificate.tag == 0x30 else { return nil }
        var certificateReader = Reader(certificate.content)
        guard let tbs = certificateReader.next(), tbs.tag == 0x30 else { return nil }

        var fields = Reader(tbs.content)
        guard var element = fields.next() else { return nil }
        if element.tag == 0xA0 {  // explicit version
            guard let serial = fields.next() else { return nil }
            element = serial
        }
        guard element.tag == 0x02 else { return nil }
        let serial = element.content.drop { $0 == 0 && element.content.count > 1 }
        _ = fields.next()  // signature algorithm
        guard let issuer = fields.next(), issuer.tag == 0x30,
            let validity = fields.next(), validity.tag == 0x30,
            let subject = fields.next(), subject.tag == 0x30
        else { return nil }

        var times = Reader(validity.content)
        guard let notBefore = times.next().flatMap(date), let notAfter = times.next().flatMap(date) else {
            return nil
        }
        _ = fields.next()  // subject public key info

        var names: [String] = []
        while let extra = fields.next() {
            guard extra.tag == 0xA3 else { continue }  // [3] extensions
            names = alternativeNames(in: extra.content)
        }

        let issuerNames = attributes(in: issuer.content)
        let subjectNames = attributes(in: subject.content)
        return CertificateInfo(
            subjectName: subjectNames.commonName, subjectOrganization: subjectNames.organization,
            issuerName: issuerNames.commonName, issuerOrganization: issuerNames.organization,
            notBefore: notBefore, notAfter: notAfter,
            serialNumber: serial.map { String(format: "%02X", $0) }.joined(separator: ":"),
            alternativeNames: names)
    }

    /// The common name and organization of a distinguished name.
    private static func attributes(in name: ArraySlice<UInt8>) -> (commonName: String?, organization: String?) {
        var common: String?
        var org: String?
        var sets = Reader(name)
        while let set = sets.next(), set.tag == 0x31 {
            var sequences = Reader(set.content)
            while let sequence = sequences.next(), sequence.tag == 0x30 {
                var pair = Reader(sequence.content)
                guard let oid = pair.next(), oid.tag == 0x06, let value = pair.next() else { continue }
                if Array(oid.content) == commonName, common == nil {
                    common = string(value)
                } else if Array(oid.content) == organization, org == nil {
                    org = string(value)
                }
            }
        }
        return (common, org)
    }

    private static func string(_ element: Element) -> String? {
        switch element.tag {
        case 0x1E:  // BMPString, UTF-16 big endian
            let units = stride(from: element.content.startIndex, to: element.content.endIndex - 1, by: 2)
                .map { UInt16(element.content[$0]) << 8 | UInt16(element.content[$0 + 1]) }
            return String(decoding: units, as: UTF16.self)
        case 0x0C, 0x13, 0x16, 0x14, 0x1A:
            return String(bytes: element.content, encoding: .utf8) ?? String(bytes: element.content, encoding: .isoLatin1)
        default:
            return nil
        }
    }

    /// UTCTime (`YYMMDDHHMMSSZ`) and GeneralizedTime (`YYYYMMDDHHMMSSZ`).
    private static func date(_ element: Element) -> Date? {
        guard element.tag == 0x17 || element.tag == 0x18,
            let text = String(bytes: element.content, encoding: .ascii), text.hasSuffix("Z")
        else { return nil }
        var digits = String(text.dropLast())
        if element.tag == 0x17 {
            guard digits.count == 12, let year = Int(digits.prefix(2)) else { return nil }
            // RFC 5280: two-digit years from 50 on are 19xx, below 50 they are 20xx.
            digits = (year >= 50 ? "19" : "20") + digits
        }
        guard digits.count == 14, digits.allSatisfy(\.isNumber) else { return nil }
        let numbers = [(0, 4), (4, 2), (6, 2), (8, 2), (10, 2), (12, 2)].map { start, length -> Int in
            let from = digits.index(digits.startIndex, offsetBy: start)
            return Int(digits[from..<digits.index(from, offsetBy: length)])!
        }
        var components = DateComponents()
        components.year = numbers[0]
        components.month = numbers[1]
        components.day = numbers[2]
        components.hour = numbers[3]
        components.minute = numbers[4]
        components.second = numbers[5]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)
    }

    private static func alternativeNames(in extensions: ArraySlice<UInt8>) -> [String] {
        var outer = Reader(extensions)
        guard let list = outer.next(), list.tag == 0x30 else { return [] }
        var entries = Reader(list.content)
        while let entry = entries.next(), entry.tag == 0x30 {
            var parts = Reader(entry.content)
            guard let oid = parts.next(), oid.tag == 0x06, Array(oid.content) == subjectAltName else { continue }
            var value = parts.next()
            if value?.tag == 0x01 { value = parts.next() }  // "critical" flag
            guard let octets = value, octets.tag == 0x04 else { return [] }
            var wrapper = Reader(octets.content)
            guard let names = wrapper.next(), names.tag == 0x30 else { return [] }
            var general = Reader(names.content)
            var result: [String] = []
            while let name = general.next() {
                switch name.tag {
                case 0x82:  // dNSName
                    if let text = String(bytes: name.content, encoding: .ascii) { result.append(text) }
                case 0x87:  // iPAddress
                    if let text = ipAddress(Array(name.content)) { result.append(text) }
                default:
                    continue
                }
            }
            return result
        }
        return []
    }

    private static func ipAddress(_ bytes: [UInt8]) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        switch bytes.count {
        case 4:
            return inet_ntop(AF_INET, bytes, &buffer, socklen_t(buffer.count)) == nil ? nil : String(nulTerminated: buffer)
        case 16:
            return inet_ntop(AF_INET6, bytes, &buffer, socklen_t(buffer.count)) == nil ? nil : String(nulTerminated: buffer)
        default:
            return nil
        }
    }
}
