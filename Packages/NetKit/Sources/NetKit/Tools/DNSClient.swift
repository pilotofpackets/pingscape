import Darwin
import Foundation

public enum DNSTransport: String, Sendable, Equatable {
    case udp = "UDP"
    case tcp = "TCP"
}

public struct DNSResponse: Sendable, Equatable {
    public let server: String
    public let transport: DNSTransport
    /// The numeric response code, and its name (`NOERROR`, `NXDOMAIN` …).
    public let responseCode: Int
    public let responseCodeName: String
    /// The header flags that are set: `AA`, `TC`, `RD`, `RA`, `AD`, `CD`.
    public let flags: [String]
    public let answers: [DNSRecord]
    public let milliseconds: Double

    public init(
        server: String, transport: DNSTransport, responseCode: Int, responseCodeName: String, flags: [String],
        answers: [DNSRecord], milliseconds: Double
    ) {
        self.server = server
        self.transport = transport
        self.responseCode = responseCode
        self.responseCodeName = responseCodeName
        self.flags = flags
        self.answers = answers
        self.milliseconds = milliseconds
    }

    static func codeName(_ code: Int) -> String {
        let names = ["NOERROR", "FORMERR", "SERVFAIL", "NXDOMAIN", "NOTIMP", "REFUSED"]
        return code < names.count ? names[code] : "RCODE\(code)"
    }

    static func flagNames(_ flags: UInt16) -> [String] {
        [(0x0400, "AA"), (0x0200, "TC"), (0x0100, "RD"), (0x0080, "RA"), (0x0020, "AD"), (0x0010, "CD")]
            .filter { flags & UInt16($0.0) != 0 }.map(\.1)
    }
}

/// A DNS client that talks to one server directly. UDP first, TCP when the
/// answer did not fit. No DNSSEC checks and no encrypted DNS.
public enum DNSClient {
    public static let timeoutMilliseconds = 5000

    /// Public resolvers offered next to the system's.
    public static let publicServers: [(name: String, address: String)] = [
        ("Cloudflare", "1.1.1.1"), ("Google", "8.8.8.8"), ("Quad9", "9.9.9.9"),
    ]

    /// The types that `ANY` is answered with. Resolvers refuse ANY (RFC 8482)
    /// or answer with a placeholder, so each type is asked for on its own.
    private static let anyTypes: [DNSRecordType] = [.a, .aaaa, .cname, .mx, .ns, .soa, .txt, .caa, .srv]

    public static func query(
        name: String, type: DNSRecordType, server: ResolvedAddress,
        timeoutMilliseconds: Int = timeoutMilliseconds
    ) async throws -> DNSResponse {
        let started = monotonicMilliseconds()
        if type == .any {
            return try await queryAll(name: name, server: server, timeoutMilliseconds: timeoutMilliseconds)
        }
        let queryName = try normalized(name)
        return try await Blocking.run { cancel in
            var response = try attempt(
                name: queryName, type: type, server: server, edns: true, timeout: timeoutMilliseconds,
                cancel: cancel, started: started)
            // Very old servers do not know EDNS and answer FORMERR. RFC 6891
            // then asks for a second try without the OPT record.
            if response.responseCode == 1 {
                response = try attempt(
                    name: queryName, type: type, server: server, edns: false, timeout: timeoutMilliseconds,
                    cancel: cancel, started: started)
            }
            return response
        }
    }

    /// A reverse lookup of an address.
    public static func reverse(
        ip: String, server: ResolvedAddress, timeoutMilliseconds: Int = timeoutMilliseconds
    ) async throws -> DNSResponse {
        guard let name = DNSMessage.reverseName(of: ip) else { throw InputError.invalidHost }
        return try await query(name: name, type: .ptr, server: server, timeoutMilliseconds: timeoutMilliseconds)
    }

    /// The round trip to one server, from a query for a name that always
    /// exists. Used for the "measure response time" button.
    public static func measure(server: ResolvedAddress, name: String = "example.com") async throws -> Double {
        try await query(name: name, type: .a, server: server, timeoutMilliseconds: 2000).milliseconds
    }

    private static func normalized(_ name: String) throws -> String {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A reverse lookup name (`4.3.2.1.in-addr.arpa`) or a service name stays as it is.
        return try ToolInput.host(text, allowUnderscore: true)
    }

    private static func queryAll(
        name: String, server: ResolvedAddress, timeoutMilliseconds: Int
    ) async throws -> DNSResponse {
        let started = monotonicMilliseconds()
        let parts = await withTaskGroup(of: DNSResponse?.self) { group in
            for type in anyTypes {
                group.addTask {
                    try? await query(name: name, type: type, server: server, timeoutMilliseconds: timeoutMilliseconds)
                }
            }
            var responses: [DNSResponse] = []
            for await response in group { if let response { responses.append(response) } }
            return responses
        }
        try Task.checkCancellation()
        // A single answer is enough for a result. Only if every query failed
        // is there nothing to show.
        guard let first = parts.first else { throw ToolError.timeout }
        let ordered = anyTypes.flatMap { type in
            parts.flatMap(\.answers).filter { $0.type == type.rawValue }
        }
        let code = parts.contains { $0.responseCode == 0 } ? 0 : first.responseCode
        return DNSResponse(
            server: first.server, transport: first.transport, responseCode: code,
            responseCodeName: DNSResponse.codeName(code), flags: first.flags, answers: ordered,
            milliseconds: monotonicMilliseconds() - started)
    }

    // MARK: One attempt

    private static func attempt(
        name: String, type: DNSRecordType, server: ResolvedAddress, edns: Bool, timeout: Int,
        cancel: CancelFlag, started: Double
    ) throws -> DNSResponse {
        let identifier = UInt16.random(in: 0...UInt16.max)
        let packet = try DNSMessage.query(
            id: identifier, name: name, type: type, ednsUDPSize: edns ? DNSMessage.ednsUDPSize : nil)
        let deadline = Deadline(afterMilliseconds: timeout)

        let reply = try udpExchange(packet, identifier: identifier, server: server, deadline: deadline, cancel: cancel)
        var parsed = try DNSMessage.parse(reply)
        var transport = DNSTransport.udp
        if needsTCP(parsed, replyBytes: reply.count, askedWithEDNS: edns) {
            let tcpReply = try tcpExchange(packet, identifier: identifier, server: server, deadline: deadline, cancel: cancel)
            parsed = try DNSMessage.parse(tcpReply)
            transport = .tcp
        }
        return DNSResponse(
            server: server.text, transport: transport, responseCode: parsed.responseCode,
            responseCodeName: DNSResponse.codeName(parsed.responseCode),
            flags: DNSResponse.flagNames(parsed.flags), answers: parsed.answers,
            milliseconds: monotonicMilliseconds() - started)
    }

    /// Whether the UDP answer has to be confirmed over TCP.
    static func needsTCP(_ message: DNSParsedMessage, replyBytes: Int, askedWithEDNS: Bool) -> Bool {
        // The normal case: the server says the answer did not fit.
        if message.isTruncated { return true }
        // The header promises more records than the packet holds.
        if message.isIncomplete { return true }
        // We offered EDNS and got no OPT back: something on the way (often the
        // DNS proxy of a router) dropped EDNS and works with the old 512 byte
        // limit. Whether it silently cut records cannot be seen in the packet,
        // so everything that is not clearly small is confirmed over TCP.
        if askedWithEDNS && !message.hasEDNS && replyBytes >= 256 { return true }
        return false
    }

    private static func udpExchange(
        _ packet: [UInt8], identifier: UInt16, server: ResolvedAddress, deadline: Deadline, cancel: CancelFlag
    ) throws -> [UInt8] {
        let socket = try POSIXSocket(family: server.family, type: SOCK_DGRAM)
        try socket.connect(to: server, port: 53, deadline: deadline, cancel: cancel)
        try socket.sendAll(packet, deadline: deadline, cancel: cancel)
        while true {
            let reply = try socket.receive(limit: 4096, deadline: deadline, cancel: cancel)
            // Ignore anything that is not the answer to our question.
            if reply.count >= 12, UInt16(reply[0]) << 8 | UInt16(reply[1]) == identifier { return reply }
        }
    }

    private static func tcpExchange(
        _ packet: [UInt8], identifier: UInt16, server: ResolvedAddress, deadline: Deadline, cancel: CancelFlag
    ) throws -> [UInt8] {
        let socket = try POSIXSocket(family: server.family, type: SOCK_STREAM)
        try socket.connect(to: server, port: 53, deadline: deadline, cancel: cancel)
        let framed = [UInt8(packet.count >> 8), UInt8(packet.count & 0xFF)] + packet
        try socket.sendAll(framed, deadline: deadline, cancel: cancel)
        let header = try socket.receiveExactly(2, deadline: deadline, cancel: cancel)
        let length = Int(header[0]) << 8 | Int(header[1])
        let reply = try socket.receiveExactly(length, deadline: deadline, cancel: cancel)
        guard reply.count >= 12, UInt16(reply[0]) << 8 | UInt16(reply[1]) == identifier else {
            throw DNSError.malformed
        }
        return reply
    }
}
