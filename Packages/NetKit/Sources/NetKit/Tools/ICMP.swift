import Darwin
import Foundation

/// What came back for an echo request.
public struct ICMPReply: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case echoReply
        /// A router dropped the packet because its hop limit ran out.
        case timeExceeded
        case unreachable
    }

    public let kind: Kind
    /// The hop limit of the reply packet (IPv4 only).
    public let ttl: UInt8?
}

/// Builds echo requests and reads replies. Pure functions, tested with recorded bytes.
enum ICMPPacket {
    static func echoRequest(ipv6: Bool, identifier: UInt16, sequence: UInt16, payloadSize: Int) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 8 + payloadSize)
        packet[0] = ipv6 ? 128 : 8
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)
        for index in 0..<payloadSize { packet[8 + index] = UInt8(index & 0xFF) }
        // The kernel fills in the ICMPv6 checksum. ICMPv4 needs it from us.
        if !ipv6 {
            let sum = checksum(packet)
            packet[2] = UInt8(sum >> 8)
            packet[3] = UInt8(sum & 0xFF)
        }
        return packet
    }

    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return UInt16(truncatingIfNeeded: ~sum)
    }

    /// Reads a reply. With `sequence` it only accepts the answer to that
    /// request, also inside the quoted copy of a "time exceeded" message. The
    /// identifier is no use for matching: on datagram sockets the kernel
    /// rewrites it. Without `sequence` any echo reply is accepted.
    static func parse(_ data: [UInt8], ipv6: Bool, sequence: UInt16?) -> ICMPReply? {
        func matches(at offset: Int) -> Bool {
            guard let sequence else { return true }
            guard offset + 8 <= data.count else { return false }
            return UInt16(data[offset + 6]) << 8 | UInt16(data[offset + 7]) == sequence
        }

        if ipv6 {
            // ICMPv6 arrives without the IP header.
            guard let type = data.first else { return nil }
            switch type {
            case 129: return matches(at: 0) ? ICMPReply(kind: .echoReply, ttl: nil) : nil
            // Time exceeded and unreachable quote the IPv6 header (40 bytes) and our packet.
            case 3: return matches(at: 8 + 40) ? ICMPReply(kind: .timeExceeded, ttl: nil) : nil
            case 1: return matches(at: 8 + 40) ? ICMPReply(kind: .unreachable, ttl: nil) : nil
            default: return nil
            }
        }

        // Darwin hands ICMPv4 over with the IP header.
        guard data.count > 20 else { return nil }
        let headerLength = Int(data[0] & 0x0F) * 4
        guard headerLength >= 20, data.count >= headerLength + 8 else { return nil }
        let ttl = data[8]
        switch data[headerLength] {
        case 0:
            return matches(at: headerLength) ? ICMPReply(kind: .echoReply, ttl: ttl) : nil
        case 11, 3:
            let innerStart = headerLength + 8
            guard data.count > innerStart + 20 else { return nil }
            let innerHeader = Int(data[innerStart] & 0x0F) * 4
            guard matches(at: innerStart + innerHeader) else { return nil }
            return ICMPReply(kind: data[headerLength] == 11 ? .timeExceeded : .unreachable, ttl: ttl)
        default:
            return nil
        }
    }
}

/// One echo request and its answer.
enum ICMPEcho {
    enum Outcome: Sendable {
        case reply(ICMPReply, from: String, milliseconds: Double, bytes: Int)
        case timeout
        /// The system gives this app no ICMP socket.
        case unsupported
        case failed(ToolError)
    }

    /// Whether an ICMP datagram socket can be opened. iOS allows it for apps.
    static func isAvailable(ipv6: Bool = false) -> Bool {
        let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_DGRAM, ipv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    /// Sends one echo request and waits for the answer. A `ttl` below the path
    /// length turns it into a traceroute step. Blocks until the answer or the timeout.
    static func send(
        to address: ResolvedAddress, sequence: UInt16, ttl: Int32 = 64, timeoutMilliseconds: Int,
        payloadSize: Int, cancel: CancelFlag
    ) throws -> Outcome {
        let socket: POSIXSocket
        do {
            socket = try POSIXSocket(
                family: address.family, type: SOCK_DGRAM,
                proto: address.isIPv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP)
        } catch {
            return .unsupported
        }
        socket.setTimeToLive(ttl, ipv6: address.isIPv6)

        let identifier = UInt16.random(in: 1...UInt16.max)
        let packet = ICMPPacket.echoRequest(
            ipv6: address.isIPv6, identifier: identifier, sequence: sequence,
            payloadSize: max(0, min(payloadSize, 1400)))
        let deadline = Deadline(afterMilliseconds: max(timeoutMilliseconds, 100))
        let started = monotonicMilliseconds()
        let sent = packet.withUnsafeBytes { raw in
            address.withSockaddr { sa, length in
                Darwin.sendto(socket.fd, raw.baseAddress, packet.count, 0, sa, length)
            }
        }
        guard sent >= 0 else { return .failed(ToolError(errno: errno)) }

        while true {
            do {
                try socket.wait(for: Int16(POLLIN), deadline: deadline, cancel: cancel)
            } catch ToolError.timeout {
                return .timeout
            }
            guard let (bytes, from) = socket.receiveFrom(limit: 2048) else { continue }
            let elapsed = monotonicMilliseconds() - started
            guard let reply = ICMPPacket.parse(bytes, ipv6: address.isIPv6, sequence: sequence)
            else { continue }
            let sender = ResolvedAddress.text(ofSockaddr: from) ?? address.text
            return .reply(reply, from: sender, milliseconds: elapsed, bytes: bytes.count)
        }
    }
}

/// Pings many addresses at once over one socket, for the LAN search.
enum ICMPSweep {
    /// Sends an echo request to each IPv4 address, at most `concurrency` open
    /// at a time, and reports every address that answers. Blocks until all
    /// are answered or timed out. Replies are matched by their source address.
    static func run(
        addresses: [String], timeoutMilliseconds: Int, concurrency: Int, cancel: CancelFlag,
        onReply: (_ address: String, _ milliseconds: Double) -> Void,
        onProgress: (_ done: Int, _ total: Int) -> Void
    ) throws {
        guard !addresses.isEmpty else { return }
        let socket: POSIXSocket
        do {
            socket = try POSIXSocket(family: AF_INET, type: SOCK_DGRAM, proto: IPPROTO_ICMP)
        } catch {
            throw ToolError.failed("ICMP not available")
        }
        // A reply from a neighbour can arrive at any moment after the send.
        var pending: [String: Double] = [:]
        var index = 0
        var done = 0
        var sequence: UInt16 = 0
        let total = addresses.count

        while (index < total || !pending.isEmpty) && !cancel.isCancelled {
            while index < total, pending.count < concurrency {
                let address = addresses[index]
                index += 1
                guard let target = ResolvedAddress(literal: address) else {
                    done += 1
                    continue
                }
                sequence &+= 1
                let packet = ICMPPacket.echoRequest(
                    ipv6: false, identifier: 1, sequence: sequence, payloadSize: 16)
                let sent = packet.withUnsafeBytes { raw in
                    target.withSockaddr { sa, length in
                        Darwin.sendto(socket.fd, raw.baseAddress, packet.count, 0, sa, length)
                    }
                }
                if sent >= 0 {
                    pending[address] = monotonicMilliseconds()
                } else {
                    done += 1
                }
            }

            var descriptor = pollfd(fd: socket.fd, events: Int16(POLLIN), revents: 0)
            _ = poll(&descriptor, 1, 20)
            while let (bytes, from) = socket.receiveFrom(limit: 2048) {
                let now = monotonicMilliseconds()
                guard let source = ResolvedAddress.text(ofSockaddr: from),
                    let started = pending[source],
                    ICMPPacket.parse(bytes, ipv6: false, sequence: nil)?.kind == .echoReply
                else { continue }
                pending[source] = nil
                done += 1
                onReply(source, now - started)
            }

            let now = monotonicMilliseconds()
            let expired = pending.filter { now - $0.value >= Double(timeoutMilliseconds) }
            for address in expired.keys { pending[address] = nil }
            done += expired.count
            onProgress(done, total)
        }
    }
}
