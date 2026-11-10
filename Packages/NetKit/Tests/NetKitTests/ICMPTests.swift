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

    @Test func takesOnlyTheReplyWithItsOwnToken() {
        let token: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        var own = ICMPPacket.echoRequest(ipv6: false, identifier: 9, sequence: 42, payloadSize: 56, token: token)
        own[0] = 0
        // Another socket's request with the same sequence (the Live tab pinging meanwhile).
        var other = ICMPPacket.echoRequest(ipv6: false, identifier: 3, sequence: 42, payloadSize: 56)
        other[0] = 0
        #expect(ICMPPacket.parse(ipv4(own), ipv6: false, sequence: 42, token: token)?.kind == .echoReply)
        #expect(ICMPPacket.parse(ipv4(other), ipv6: false, sequence: 42, token: token) == nil)
        var ownV6 = ICMPPacket.echoRequest(ipv6: true, identifier: 1, sequence: 7, payloadSize: 8, token: token)
        ownV6[0] = 129
        #expect(ICMPPacket.parse(ownV6, ipv6: true, sequence: 7, token: token)?.kind == .echoReply)
        #expect(ICMPPacket.parse(ownV6, ipv6: true, sequence: 7, token: [9, 9])?.kind == nil)
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

    @Test func readsFragmentationNeededWithTheNextHopMTU() {
        let original = ICMPPacket.echoRequest(ipv6: false, identifier: 9, sequence: 5, payloadSize: 1444)
        var quotedHeader = [UInt8](repeating: 0, count: 20)
        quotedHeader[0] = 0x45
        // As a PPPoE router sent it on 2026-11-10: type 3, code 4, next-hop MTU 1492.
        let icmp: [UInt8] = [3, 4, 0, 0, 0, 0, 0x05, 0xD4] + quotedHeader + Array(original.prefix(8))
        #expect(ICMPPacket.parse(ipv4(icmp), ipv6: false, sequence: 5)?.kind == .tooBig(mtu: 1492))
        let silent: [UInt8] = [3, 4, 0, 0, 0, 0, 0, 0] + quotedHeader + Array(original.prefix(8))
        #expect(ICMPPacket.parse(ipv4(silent), ipv6: false, sequence: 5)?.kind == .tooBig(mtu: nil))
        #expect(ICMPPacket.parse(ipv4(icmp), ipv6: false, sequence: 6) == nil)
    }

    @Test func readsPacketTooBigForIPv6() {
        let quoted = [UInt8](repeating: 0, count: 40)
            + Array(ICMPPacket.echoRequest(ipv6: true, identifier: 1, sequence: 3, payloadSize: 0))
        let tooBig: [UInt8] = [2, 0, 0, 0, 0, 0, 0x05, 0x00] + quoted
        #expect(ICMPPacket.parse(tooBig, ipv6: true, sequence: 3)?.kind == .tooBig(mtu: 1280))
        #expect(ICMPPacket.parse(tooBig, ipv6: true, sequence: 4) == nil)
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

@Suite("Path MTU search")
struct PathMTUSearchTests {
    /// Runs the search against a path that carries packets up to `mtu`.
    private func run(
        ceiling: Int, small: Int = 84, answer: (Int) -> PathMTUProbe.Result
    ) -> (sizes: [Int], result: Int?) {
        var search = PathMTUSearch(small: small, ceiling: ceiling)
        var sizes: [Int] = []
        while let size = search.next, sizes.count < 40 {
            sizes.append(size)
            search.record(size: size, result: answer(size))
        }
        return (sizes, search.largestPassed)
    }

    @Test func stopsAfterOneProbeWhenTheFullSizePasses() {
        let run = run(ceiling: 1500) { _ in .passed(milliseconds: 10) }
        #expect(run.sizes == [1500])
        #expect(run.result == 1500)
    }

    @Test func triesTheSizeARouterNames() {
        let run = run(ceiling: 1500) { size in
            size <= 1492 ? .passed(milliseconds: 10) : .tooBig(mtu: 1492, reportedBy: "10.10.20.1")
        }
        #expect(run.sizes == [1500, 84, 1492])
        #expect(run.result == 1492)
    }

    @Test func findsASilentLimitByHalving() {
        // A tunnel that drops larger packets without a message.
        let run = run(ceiling: 1500) { size in size <= 1420 ? .passed(milliseconds: 10) : .noReply }
        #expect(run.result == 1420)
        #expect(run.sizes.count <= 14)
    }

    @Test func findsALimitWhenTheRouterNamesNoMTU() {
        let run = run(ceiling: 1500) { size in
            size <= 1400 ? .passed(milliseconds: 10) : .tooBig(mtu: nil, reportedBy: "192.0.2.1")
        }
        #expect(run.result == 1400)
    }

    @Test func givesUpWhenNotEvenASmallPacketComesBack() {
        let run = run(ceiling: 1500) { _ in .noReply }
        #expect(run.sizes == [1500, 84])
        #expect(run.result == nil)
    }

    @Test func ignoresANamedMTUThatIsNoSmaller() {
        let run = run(ceiling: 1500) { size in
            size <= 1300 ? .passed(milliseconds: 10) : .tooBig(mtu: 1500, reportedBy: "192.0.2.1")
        }
        #expect(run.result == 1300)
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
    @Test(.enabled(if: ICMPEcho.isAvailable())) func pingsTheLoopbackWithALargeUnfragmentedPacket() async {
        let settings = PingSettings(payloadSize: 9000, dontFragment: true, intervalSeconds: 0.05)
        var bytes: Int?
        for await event in PingTool.run(address: loopback, settings: settings) {
            if case .reply(_, let size, _, _) = event { bytes = size; break }
            if case .noReply = event { break }
            if case .failed = event { break }
        }
        // The reply comes with its IPv4 header.
        #expect(bytes == 9028)
    }

    // Needs an ICMP datagram socket, which a locked-down CI machine may not give.
    @Test(.enabled(if: ICMPEcho.isAvailable())) func findsTheMTUOfTheLoopback() async {
        var interfaceMTU: Int?
        var pathMTU: Int?
        for await event in PathMTUTool.run(address: loopback, timeoutSeconds: 1) {
            if case .started(_, _, let mtu) = event { interfaceMTU = mtu }
            if case .finished(let mtu) = event { pathMTU = mtu }
        }
        #expect(interfaceMTU != nil)
        #expect(pathMTU == interfaceMTU)
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

@Suite("STUN")
struct STUNTests {
    private let transaction: [UInt8] = Array(1...12)

    /// A binding success response with one attribute.
    private func response(type: UInt16, value: [UInt8], transaction: [UInt8]? = nil) -> [UInt8] {
        let attribute = [UInt8(type >> 8), UInt8(type & 0xFF), 0, UInt8(value.count)] + value
        return [0x01, 0x01, 0, UInt8(attribute.count), 0x21, 0x12, 0xA4, 0x42] + (transaction ?? self.transaction)
            + attribute
    }

    @Test func buildsABindingRequest() {
        let request = STUNMessage.bindingRequest(transactionID: transaction)
        #expect(request.count == 20)
        #expect(Array(request[0..<8]) == [0, 1, 0, 0, 0x21, 0x12, 0xA4, 0x42])
    }

    @Test func readsAnXORMappedIPv4Address() {
        // 203.0.113.5:40000, XORed with the cookie: port ^ 0x2112, address ^ 21 12 A4 42.
        let value: [UInt8] = [0, 1, 0x9C ^ 0x21, 0x40 ^ 0x12, 203 ^ 0x21, 0 ^ 0x12, 113 ^ 0xA4, 5 ^ 0x42]
        let found = STUNMessage.mappedAddress(in: response(type: 0x0020, value: value), transactionID: transaction)
        #expect(found?.address == "203.0.113.5")
        #expect(found?.port == 40000)
        // Another transaction's answer is not ours.
        #expect(STUNMessage.mappedAddress(in: response(type: 0x0020, value: value), transactionID: Array(repeating: 0, count: 12)) == nil)
    }

    @Test func readsAnXORMappedIPv6Address() {
        let address: [UInt8] = [0x20, 0x01, 0x0D, 0xB8] + Array(repeating: 0, count: 11) + [1]
        let key: [UInt8] = [0x21, 0x12, 0xA4, 0x42] + transaction
        let xored = zip(address, key).map { $0 ^ $1 }
        let value: [UInt8] = [0, 2, 0x13 ^ 0x21, 0x88 ^ 0x12] + xored
        let found = STUNMessage.mappedAddress(in: response(type: 0x0020, value: value), transactionID: transaction)
        #expect(found?.address == "2001:db8::1")
        #expect(found?.port == 5000)
    }

    @Test func fallsBackToThePlainMappedAddress() {
        let value: [UInt8] = [0, 1, 0x0D, 0x96, 198, 51, 100, 7]
        let found = STUNMessage.mappedAddress(in: response(type: 0x0001, value: value), transactionID: transaction)
        #expect(found?.address == "198.51.100.7")
        #expect(found?.port == 3478)
    }

    private func mapping(_ server: String, at serverAddress: String, _ address: String, _ port: UInt16) -> STUNMapping {
        STUNMapping(
            server: STUNServer(host: server), serverAddress: serverAddress, publicAddress: address, publicPort: port,
            milliseconds: 10, error: nil)
    }

    @Test func reportsTheFactsOfAMapping() {
        let same = STUNReport(
            localAddress: "192.168.1.20", localPort: 50000,
            mappings: [mapping("a", at: "192.0.2.1", "203.0.113.5", 50000), mapping("b", at: "192.0.2.2", "203.0.113.5", 50000)])
        #expect(same.isTranslated == true)
        #expect(same.keepsPort == true)
        #expect(same.sameMappingForAllServers == true)

        let changing = STUNReport(
            localAddress: "192.168.1.20", localPort: 50000,
            mappings: [mapping("a", at: "192.0.2.1", "203.0.113.5", 61000), mapping("b", at: "192.0.2.2", "203.0.113.5", 61001)])
        #expect(changing.keepsPort == false)
        #expect(changing.sameMappingForAllServers == false)

        let direct = STUNReport(
            localAddress: "2001:db8::20", localPort: 50000,
            mappings: [mapping("a", at: "2001:db8::1", "2001:db8::20", 50000)])
        #expect(direct.isTranslated == false)
        // One server cannot tell whether the mapping depends on the destination.
        #expect(direct.sameMappingForAllServers == nil)
    }
}

@Suite("MTR")
struct MTRTests {
    @Test func collectsStatisticsAndEveryAddressOfAHop() {
        var hop = MTRHop(number: 3)
        hop.record(("192.0.2.1", 10))
        hop.record(nil)
        hop.record(("192.0.2.2", 14))
        hop.record(("192.0.2.1", 12))
        #expect(hop.addresses == ["192.0.2.1", "192.0.2.2"])
        #expect(hop.statistics.sent == 4)
        #expect(hop.statistics.lostPercent == 25)
        #expect(hop.statistics.minimum == 10)
        #expect(hop.last == 12)
        hop.record(nil)
        #expect(hop.last == nil)
    }

    // Needs an ICMP datagram socket, which a locked-down CI machine may not give.
    @Test(.enabled(if: ICMPEcho.isAvailable())) func tracesTheLoopbackInRounds() async {
        let loopback = ResolvedAddress(literal: "127.0.0.1")!
        var last: [MTRHop] = []
        var reached = false
        var rounds = 0
        for await event in MTRTool.run(
            address: loopback, settings: TracerouteSettings(maximumHops: 5, timeoutSeconds: 1, resolveNames: false),
            intervalSeconds: 0.05)
        {
            if case .round(let number, let hops, let target) = event {
                rounds = number
                last = hops
                reached = target
                if number == 3 { break }
            }
            if case .failed = event { break }
        }
        #expect(rounds == 3)
        #expect(reached)
        #expect(last.count == 1)
        #expect(last.first?.addresses == ["127.0.0.1"])
        #expect(last.first?.statistics.received == 3)
    }
}
