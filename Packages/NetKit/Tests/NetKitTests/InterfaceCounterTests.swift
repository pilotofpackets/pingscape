import Darwin
import Testing

@testable import NetKit

/// Builds `RTM_IFINFO2` messages the way `sysctl NET_RT_IFLIST2` returns them.
private enum CounterFixture {
    static func message(
        index: Int, type: UInt8 = InterfaceCounterParser.interfaceInfo2,
        receivedBytes: UInt64 = 0, sentBytes: UInt64 = 0,
        receivedPackets: UInt64 = 0, sentPackets: UInt64 = 0
    ) -> [UInt8] {
        var header = if_msghdr2()
        header.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
        header.ifm_type = type
        header.ifm_index = UInt16(index)
        header.ifm_data.ifi_ibytes = receivedBytes
        header.ifm_data.ifi_obytes = sentBytes
        header.ifm_data.ifi_ipackets = receivedPackets
        header.ifm_data.ifi_opackets = sentPackets
        return withUnsafeBytes(of: &header) { Array($0) }
    }
}

@Suite("Interface counters")
struct InterfaceCounterTests {
    @Test func readsCountersBeyond4GiB() {
        let sixGiB: UInt64 = 6 * 1024 * 1024 * 1024
        let buffer = CounterFixture.message(
            index: 6, receivedBytes: sixGiB, sentBytes: 88_000_000,
            receivedPackets: 4_400_000_000, sentPackets: 640_000)
        #expect(
            InterfaceCounterParser.counters(in: buffer) == [
                6: InterfaceCounters(
                    receivedBytes: sixGiB, sentBytes: 88_000_000,
                    receivedPackets: 4_400_000_000, sentPackets: 640_000)
            ])
    }

    @Test func readsSeveralInterfacesAndSkipsOtherMessageTypes() {
        let buffer =
            CounterFixture.message(index: 1, receivedBytes: 10)
            // An address message (`RTM_NEWADDR`) sits between the interface messages.
            + CounterFixture.message(index: 99, type: 0x0C, receivedBytes: 999)
            + CounterFixture.message(index: 6, receivedBytes: 20)
        let counters = InterfaceCounterParser.counters(in: buffer)
        #expect(counters.keys.sorted() == [1, 6])
        #expect(counters[6]?.receivedBytes == 20)
    }

    @Test func ignoresTruncatedAndEmptyBuffers() {
        #expect(InterfaceCounterParser.counters(in: []).isEmpty)
        let whole = CounterFixture.message(index: 6, receivedBytes: 20)
        #expect(InterfaceCounterParser.counters(in: Array(whole.dropLast())).isEmpty)
        // A length of zero must end the loop, not spin.
        #expect(InterfaceCounterParser.counters(in: [0, 0, 0, 0x12, 0, 0, 0, 0]).isEmpty)
    }

    /// The layout comes from the SDK header, so this pins the numbers that the
    /// Darwin ABI promises: the statistics start after 32 bytes, and the byte
    /// counters follow at 64 and 72 bytes into `if_data64`.
    @Test func layoutMatchesTheDarwinABI() {
        #expect(MemoryLayout<if_msghdr2>.offset(of: \.ifm_data) == 32)
        #expect(MemoryLayout<if_data64>.offset(of: \.ifi_ibytes) == 64)
        #expect(MemoryLayout<if_data64>.offset(of: \.ifi_obytes) == 72)
    }

    /// Checks the real kernel answer against the 32-bit counters of
    /// `getifaddrs`. Their low 32 bits must match, apart from traffic that
    /// arrives between the two calls. A wrong layout would give random values.
    @Test func liveCountersMatchTheLow32BitsOfGetifaddrs() {
        var head: UnsafeMutablePointer<ifaddrs>?
        #expect(getifaddrs(&head) == 0)
        defer { freeifaddrs(head) }
        let counters = InterfaceCounterCollector.collect()

        var compared = 0
        var cursor = head
        while let entry = cursor {
            cursor = entry.pointee.ifa_next
            guard let address = entry.pointee.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                let data = entry.pointee.ifa_data,
                let live = counters[Int(if_nametoindex(entry.pointee.ifa_name))]
            else { continue }
            let small = data.assumingMemoryBound(to: if_data.self).pointee
            let delta = UInt32(truncatingIfNeeded: live.receivedBytes) &- small.ifi_ibytes
            #expect(delta < 64 * 1024 * 1024, "\(String(cString: entry.pointee.ifa_name)) differs by \(delta)")
            compared += 1
        }
        #expect(compared > 0)
    }

    @Test func collectorFillsCountersAndFlags() throws {
        let loopback = try #require(InterfaceCollector.collect().first { $0.name == "lo0" })
        #expect(loopback.flags.contains(.loopback))
        #expect(loopback.isRunning)
        #expect(loopback.receivedBytes != nil)
        #expect(loopback.sentPackets != nil)
    }
}

@Suite("Interface flags")
struct InterfaceFlagsTests {
    @Test func namesFollowAFixedOrder() {
        let flags: InterfaceFlags = [.running, .multicast, .up, .pointToPoint]
        #expect(flags.names == ["UP", "POINTOPOINT", "RUNNING", "MULTICAST"])
    }

    @Test func aFixtureInterfaceDefaultsToUpAndRunning() {
        #expect(NetworkInterface(name: "en0").isRunning)
        #expect(!NetworkInterface(name: "en0", isUp: false).isRunning)
    }
}
