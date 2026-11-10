import Darwin
import Foundation

/// The answer of one time server (SNTP, RFC 4330).
public struct NTPResult: Sendable, Equatable {
    /// How far the server's clock is ahead of this device's, in milliseconds.
    /// Negative: the device is ahead.
    public let offsetMilliseconds: Double
    /// The round trip without the server's own processing time.
    public let delayMilliseconds: Double
    /// 1 for a server with its own reference clock, more for each step away.
    /// 0 is a "kiss of death": the server refuses to answer.
    public let stratum: Int
    /// For stratum 1 the name of the clock (`GPS`, `PPS` …), for a kiss of
    /// death its code (`RATE` …), otherwise the address of the upstream server.
    public let reference: String?
    /// The server's time when it sent the answer.
    public let serverTime: Date
    /// 1 or 2 when a leap second is announced for the end of the day, 3 when
    /// the server's clock is not synchronized.
    public let leapIndicator: Int

    public init(
        offsetMilliseconds: Double, delayMilliseconds: Double, stratum: Int, reference: String?, serverTime: Date,
        leapIndicator: Int
    ) {
        self.offsetMilliseconds = offsetMilliseconds
        self.delayMilliseconds = delayMilliseconds
        self.stratum = stratum
        self.reference = reference
        self.serverTime = serverTime
        self.leapIndicator = leapIndicator
    }
}

enum NTPPacket {
    /// Seconds from 1900 (NTP) to 1970 (Unix).
    static let epochOffset = 2_208_988_800.0

    static func timestamp(_ date: Date) -> [UInt8] {
        let seconds = date.timeIntervalSince1970 + epochOffset
        let whole = UInt32(truncatingIfNeeded: Int64(seconds))
        let fraction = UInt32(truncatingIfNeeded: Int64((seconds - seconds.rounded(.down)) * 4_294_967_296))
        return [whole, fraction].flatMap { value in (0..<4).map { UInt8(truncatingIfNeeded: value >> (24 - $0 * 8)) } }
    }

    static func date(_ bytes: ArraySlice<UInt8>) -> Date {
        let values = stride(from: bytes.startIndex, to: bytes.startIndex + 8, by: 4).map { start in
            bytes[start..<(start + 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        }
        let seconds = Double(values[0]) + Double(values[1]) / 4_294_967_296
        return Date(timeIntervalSince1970: seconds - epochOffset)
    }

    /// A client request: version 4, mode 3, the send time as transmit timestamp.
    static func request(sentAt: Date) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 48)
        packet[0] = 0x23
        packet.replaceSubrange(40..<48, with: timestamp(sentAt))
        return packet
    }

    /// Reads a server answer to `request`, sent at `sentAt` and received at `receivedAt`.
    static func parse(_ data: [UInt8], request: [UInt8], sentAt: Date, receivedAt: Date) -> NTPResult? {
        guard data.count >= 48, data[0] & 0x07 == 4,
            // The server copies our transmit timestamp into its originate field.
            Array(data[24..<32]) == Array(request[40..<48])
        else { return nil }
        let stratum = Int(data[1])
        let received = date(data[32..<40])
        let transmitted = date(data[40..<48])
        let t1 = sentAt.timeIntervalSince1970
        let t2 = received.timeIntervalSince1970
        let t3 = transmitted.timeIntervalSince1970
        let t4 = receivedAt.timeIntervalSince1970
        let referenceBytes = Array(data[12..<16])
        let reference: String?
        if stratum <= 1 {
            let text = String(decoding: referenceBytes.prefix { $0 != 0 }, as: UTF8.self)
            reference = text.isEmpty ? nil : text
        } else {
            reference = referenceBytes.map(String.init).joined(separator: ".")
        }
        return NTPResult(
            offsetMilliseconds: ((t2 - t1) + (t3 - t4)) / 2 * 1000,
            delayMilliseconds: ((t4 - t1) - (t3 - t2)) * 1000,
            stratum: stratum, reference: reference, serverTime: transmitted, leapIndicator: Int(data[0] >> 6))
    }
}

public enum NTPClient {
    public static let defaultServers = ["time.apple.com", "time.cloudflare.com", "pool.ntp.org"]

    /// One request to `host`, port 123. Resent once when nothing comes back.
    public static func query(host: String, timeoutMilliseconds: Int = 3000) async throws -> NTPResult {
        guard let address = try await HostResolver.resolve(host).first else { throw ToolError.cannotResolve }
        return try await Blocking.run { cancel in
            let socket = try POSIXSocket(family: address.family, type: SOCK_DGRAM)
            let deadline = Deadline(afterMilliseconds: timeoutMilliseconds)
            try socket.connect(to: address, port: 123, deadline: deadline, cancel: cancel)
            for attempt in 0..<2 {
                let sentAt = Date()
                let request = NTPPacket.request(sentAt: sentAt)
                try socket.sendAll(request, deadline: deadline, cancel: cancel)
                let wait = Deadline(afterMilliseconds: attempt == 0 ? timeoutMilliseconds / 2 : timeoutMilliseconds)
                while true {
                    let reply: [UInt8]
                    do {
                        reply = try socket.receive(limit: 512, deadline: wait, cancel: cancel)
                    } catch ToolError.timeout {
                        break
                    }
                    let receivedAt = Date()
                    if let result = NTPPacket.parse(reply, request: request, sentAt: sentAt, receivedAt: receivedAt) {
                        return result
                    }
                }
                if deadline.remainingMilliseconds == 0 { break }
            }
            throw ToolError.timeout
        }
    }
}
