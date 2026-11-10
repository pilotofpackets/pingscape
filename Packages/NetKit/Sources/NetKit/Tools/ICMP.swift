import Darwin
import Foundation

/// What came back for an echo request.
public struct ICMPReply: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case echoReply
        /// A router dropped the packet because its hop limit ran out.
        case timeExceeded
        case unreachable
        /// A router could not forward the packet without fragmenting it, and
        /// the packet said "don't fragment" (IPv6 never fragments on the way).
        /// `mtu` is the largest packet the next link takes, if the router said.
        case tooBig(mtu: Int?)
    }

    public let kind: Kind
    /// The hop limit of the reply packet (IPv4 only).
    public let ttl: UInt8?
}

/// Builds echo requests and reads replies. Pure functions, tested with recorded bytes.
enum ICMPPacket {
    /// `token` goes first into the payload (as far as it fits), so the answer
    /// can be told apart from one to another socket with the same sequence.
    static func echoRequest(
        ipv6: Bool, identifier: UInt16, sequence: UInt16, payloadSize: Int, token: [UInt8] = []
    ) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 8 + payloadSize)
        packet[0] = ipv6 ? 128 : 8
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)
        for index in 0..<payloadSize { packet[8 + index] = UInt8(index & 0xFF) }
        for (index, byte) in token.prefix(payloadSize).enumerated() { packet[8 + index] = byte }
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
    /// rewrites it. Without `sequence` any echo reply is accepted. With
    /// `token` an echo reply must also carry it at the start of its payload
    /// (two pings at once, the Live tab and the Ping tool, share sequence numbers).
    static func parse(_ data: [UInt8], ipv6: Bool, sequence: UInt16?, token: [UInt8] = []) -> ICMPReply? {
        func matches(at offset: Int) -> Bool {
            guard let sequence else { return true }
            guard offset + 8 <= data.count else { return false }
            return UInt16(data[offset + 6]) << 8 | UInt16(data[offset + 7]) == sequence
        }
        func carriesToken(at offset: Int) -> Bool {
            guard offset + 8 + token.count <= data.count else { return token.isEmpty }
            return Array(data[(offset + 8)..<(offset + 8 + token.count)]) == token
        }

        if ipv6 {
            // ICMPv6 arrives without the IP header.
            guard let type = data.first else { return nil }
            switch type {
            case 129: return matches(at: 0) && carriesToken(at: 0) ? ICMPReply(kind: .echoReply, ttl: nil) : nil
            // Packet too big carries the MTU of the next link in bytes 4 to 7.
            case 2:
                guard matches(at: 8 + 40) else { return nil }
                let mtu = data[4...7].reduce(0) { $0 << 8 | Int($1) }
                return ICMPReply(kind: .tooBig(mtu: mtu > 0 ? mtu : nil), ttl: nil)
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
            return matches(at: headerLength) && carriesToken(at: headerLength)
                ? ICMPReply(kind: .echoReply, ttl: ttl) : nil
        case 11, 3:
            let innerStart = headerLength + 8
            guard data.count > innerStart + 20 else { return nil }
            let innerHeader = Int(data[innerStart] & 0x0F) * 4
            guard matches(at: innerStart + innerHeader) else { return nil }
            if data[headerLength] == 11 { return ICMPReply(kind: .timeExceeded, ttl: ttl) }
            // Code 4, fragmentation needed: bytes 6 and 7 hold the MTU of the
            // next link (RFC 1191). Older routers leave them zero.
            if data[headerLength + 1] == 4 {
                let mtu = Int(data[headerLength + 6]) << 8 | Int(data[headerLength + 7])
                return ICMPReply(kind: .tooBig(mtu: mtu > 0 ? mtu : nil), ttl: ttl)
            }
            return ICMPReply(kind: .unreachable, ttl: ttl)
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
        /// The system did not send the packet: with "don't fragment" it is
        /// larger than the MTU of the interface it would leave on.
        case tooBigToSend
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
        payloadSize: Int, dontFragment: Bool = false, cancel: CancelFlag
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
        if dontFragment { socket.setDontFragment(ipv6: address.isIPv6) }

        let identifier = UInt16.random(in: 1...UInt16.max)
        let size = max(0, min(payloadSize, PingSettings.maximumPayloadSize))
        let token = (0..<min(size, 8)).map { _ in UInt8.random(in: 0...255) }
        let packet = ICMPPacket.echoRequest(
            ipv6: address.isIPv6, identifier: identifier, sequence: sequence, payloadSize: size, token: token)
        // The default buffers of an ICMP socket hold 8 KiB (net.inet.raw.maxdgram):
        // a larger request fails with EMSGSIZE even when it may be fragmented.
        // Every ICMP socket also gets a copy of every ICMP answer, so with
        // other pings running the buffer needs room for theirs next to ours.
        let receiveLimit = packet.count + 128
        socket.setBufferSizes(max(receiveLimit * 4, 65536))
        let deadline = Deadline(afterMilliseconds: max(timeoutMilliseconds, 100))
        let started = monotonicMilliseconds()
        let sent = packet.withUnsafeBytes { raw in
            address.withSockaddr { sa, length in
                Darwin.sendto(socket.fd, raw.baseAddress, packet.count, 0, sa, length)
            }
        }
        if sent < 0, errno == EMSGSIZE, dontFragment { return .tooBigToSend }
        guard sent >= 0 else { return .failed(ToolError(errno: errno)) }

        while true {
            do {
                try socket.wait(for: Int16(POLLIN), deadline: deadline, cancel: cancel)
            } catch ToolError.timeout {
                return .timeout
            }
            guard let (bytes, from) = socket.receiveFrom(limit: max(receiveLimit, 2048)) else { continue }
            let elapsed = monotonicMilliseconds() - started
            guard let reply = ICMPPacket.parse(bytes, ipv6: address.isIPv6, sequence: sequence, token: token)
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
