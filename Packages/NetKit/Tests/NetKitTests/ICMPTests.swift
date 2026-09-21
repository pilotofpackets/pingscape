import Darwin
import Foundation
import Testing

@testable import NetKit

@Suite("ICMP packets")
struct ICMPPacketTests {
    @Test func buildsAnEchoRequestWithAValidChecksum() {
        let packet = ICMPPacket.echoRequest(ipv6: false, identifier: 0x1234, sequence: 7, payloadSize: 8)
        #expect(packet.count == 16)
        #expect(Array(packet[0...1]) == [8, 0])
        #expect(Array(packet[4...7]) == [0x12, 0x34, 0, 7])
        // A packet with a correct checksum sums to zero.
        #expect(ICMPPacket.checksum(packet) == 0)
    }

    @Test func leavesTheICMPv6ChecksumToTheKernel() {
        let packet = ICMPPacket.echoRequest(ipv6: true, identifier: 1, sequence: 1, payloadSize: 0)
        #expect(packet[0] == 128)
        #expect(Array(packet[2...3]) == [0, 0])
    }

    /// An IPv4 header (20 bytes, TTL 57) followed by `icmp`.
    private func ipv4(_ icmp: [UInt8], ttl: UInt8 = 57) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 20)
        header[0] = 0x45
        header[8] = ttl
        header[9] = 1
        return header + icmp
    }

    @Test func readsAnEchoReply() {
        var icmp = ICMPPacket.echoRequest(ipv6: false, identifier: 9, sequence: 42, payloadSize: 4)
        icmp[0] = 0
        let reply = ICMPPacket.parse(ipv4(icmp), ipv6: false, sequence: 42)
        #expect(reply == ICMPReply(kind: .echoReply, ttl: 57))
        #expect(ICMPPacket.parse(ipv4(icmp), ipv6: false, sequence: 43) == nil)
        #expect(ICMPPacket.parse(ipv4(icmp), ipv6: false, sequence: nil)?.kind == .echoReply)
    }

    @Test func readsTimeExceededThroughTheQuotedRequest() {
        let original = ICMPPacket.echoRequest(ipv6: false, identifier: 9, sequence: 5, payloadSize: 4)
        var quotedHeader = [UInt8](repeating: 0, count: 20)
        quotedHeader[0] = 0x45
        // type 11, code 0, checksum, 4 unused bytes, then the quoted IP header and 8 bytes of our packet.
        let icmp: [UInt8] = [11, 0, 0, 0, 0, 0, 0, 0] + quotedHeader + Array(original.prefix(8))
        let reply = ICMPPacket.parse(ipv4(icmp, ttl: 250), ipv6: false, sequence: 5)
        #expect(reply == ICMPReply(kind: .timeExceeded, ttl: 250))
        #expect(ICMPPacket.parse(ipv4(icmp), ipv6: false, sequence: 6) == nil)
    }

    @Test func readsUnreachable() {
        let original = ICMPPacket.echoRequest(ipv6: false, identifier: 9, sequence: 5, payloadSize: 4)
        var quotedHeader = [UInt8](repeating: 0, count: 20)
        quotedHeader[0] = 0x45
        let icmp: [UInt8] = [3, 1, 0, 0, 0, 0, 0, 0] + quotedHeader + Array(original.prefix(8))
        #expect(ICMPPacket.parse(ipv4(icmp), ipv6: false, sequence: 5)?.kind == .unreachable)
    }

    @Test func readsICMPv6WithoutAnIPHeader() {
        var reply = ICMPPacket.echoRequest(ipv6: true, identifier: 1, sequence: 3, payloadSize: 0)
        reply[0] = 129
        #expect(ICMPPacket.parse(reply, ipv6: true, sequence: 3)?.kind == .echoReply)
        let quoted = [UInt8](repeating: 0, count: 40) + Array(ICMPPacket.echoRequest(ipv6: true, identifier: 1, sequence: 3, payloadSize: 0))
        let exceeded: [UInt8] = [3, 0, 0, 0, 0, 0, 0, 0] + quoted
        #expect(ICMPPacket.parse(exceeded, ipv6: true, sequence: 3)?.kind == .timeExceeded)
    }

    @Test func ignoresShortAndUnrelatedPackets() {
        #expect(ICMPPacket.parse([], ipv6: false, sequence: nil) == nil)
        #expect(ICMPPacket.parse([0x45, 0, 0], ipv6: false, sequence: nil) == nil)
        #expect(ICMPPacket.parse(ipv4([13, 0, 0, 0, 0, 0, 0, 0, 0, 0]), ipv6: false, sequence: nil) == nil)
    }
}

@Suite("Ping statistics")
struct PingStatisticsTests {
    @Test func countsLossAndComputesJitter() {
        var stats = PingStatistics()
        stats.recordReply(milliseconds: 10)
        stats.recordReply(milliseconds: 14)
        stats.recordLoss()
        stats.recordReply(milliseconds: 12)
        #expect(stats.sent == 4)
        #expect(stats.received == 3)
        #expect(stats.lostPercent == 25)
        #expect(stats.minimum == 10)
        #expect(stats.maximum == 14)
        #expect(stats.average == 12)
        // |14 - 10| = 4 and |12 - 14| = 2: the mean is 3.
        #expect(stats.jitter == 3)
    }

    @Test func hasNoValuesBeforeTheFirstReply() {
        var stats = PingStatistics()
        #expect(stats.average == nil)
        #expect(stats.jitter == nil)
        #expect(stats.lostPercent == 0)
        stats.recordLoss()
        #expect(stats.lostPercent == 100)
        #expect(stats.average == nil)
        stats.recordReply(milliseconds: 5)
        #expect(stats.jitter == nil)
    }
}

@Suite("Tools on this machine")
struct LoopbackToolTests {
    private let loopback = ResolvedAddress(literal: "127.0.0.1")!

    @Test func resolvesLiteralsWithoutTheNetwork() async throws {
        let addresses = try await HostResolver.resolve("127.0.0.1")
        #expect(addresses.map(\.text) == ["127.0.0.1"])
        #expect(ResolvedAddress(literal: "::1")?.isIPv6 == true)
        #expect(ResolvedAddress(literal: "example.com") == nil)
    }

    // Needs an ICMP datagram socket, which a locked-down CI machine may not give.
    @Test(.enabled(if: ICMPEcho.isAvailable())) func pingsTheLoopback() async {
        var settings = PingSettings()
        settings.intervalSeconds = 0.05
        var replies = 0
        var method: PingMethod?
        var events = 0
        for await event in PingTool.run(address: loopback, settings: settings) {
            events += 1
            switch event {
            case .started(_, let started): method = started
            case .reply(_, _, let milliseconds, _):
                #expect(milliseconds >= 0 && milliseconds < 1000)
                replies += 1
            default: break
            }
            if replies == 3 { break }
            if events > 30 { break }
        }
        #expect(replies == 3)
        #expect(method != nil)
    }

    // Needs an ICMP datagram socket, which a locked-down CI machine may not give.
    @Test(.enabled(if: ICMPEcho.isAvailable())) func pingTracesTheLoopbackInOneHop() async {
        var hops: [TracerouteHop] = []
        var reached: Bool?
        for await event in TracerouteTool.run(
            address: loopback, settings: TracerouteSettings(probesPerHop: 1, timeoutSeconds: 1, resolveNames: false))
        {
            if case .hop(let hop) = event { hops.append(hop) }
            if case .finished(let value) = event { reached = value }
        }
        #expect(hops.count == 1)
        #expect(hops.first?.address == "127.0.0.1")
        #expect(reached == true)
    }

    // Needs an ICMP datagram socket, which a locked-down CI machine may not give.
    @Test(.enabled(if: ICMPEcho.isAvailable())) func sweepFindsTheLoopback() throws {
        let cancel = CancelFlag()
        var found: [String] = []
        try ICMPSweep.run(
            addresses: ["127.0.0.1"], timeoutMilliseconds: 500, concurrency: 8, cancel: cancel,
            onReply: { address, _ in found.append(address) }, onProgress: { _, _ in })
        #expect(found == ["127.0.0.1"])
    }
}
