import Darwin
import Testing

@testable import NetKit

@Suite("Full routing table")
struct RouteTableTests {
    private static let names: [Int: String] = [6: "en0", 8: "utun4"]

    /// A sockaddr with a length, a family and the address bytes after a header of `header` bytes.
    private func sockaddr(length: Int, family: Int32, header: Int, bytes: [UInt8]) -> [UInt8] {
        // A sockaddr of length 0 still takes four bytes in the message.
        guard length > 0 else { return [0, 0, 0, 0] }
        var raw = [UInt8](repeating: 0, count: length)
        raw[0] = UInt8(length)
        raw[1] = UInt8(family)
        for (index, byte) in bytes.enumerated() where header + index < length { raw[header + index] = byte }
        // Pad to a multiple of four, as the kernel does.
        while raw.count % 4 != 0 { raw.append(0) }
        return raw
    }

    private func message(index: Int, flags: Int32, addrs: Int32, body: [[UInt8]]) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: RouteMessageParser.headerSize)
        let bytes = body.flatMap { $0 }
        let length = header.count + bytes.count
        header[0] = UInt8(length & 0xFF)
        header[1] = UInt8(length >> 8)
        header[4] = UInt8(index)
        for byte in 0..<4 { header[8 + byte] = UInt8((UInt32(bitPattern: flags) >> (8 * UInt32(byte))) & 0xFF) }
        for byte in 0..<4 { header[12 + byte] = UInt8((UInt32(bitPattern: addrs) >> (8 * UInt32(byte))) & 0xFF) }
        return header + bytes
    }

    private func parse(_ buffer: [UInt8], ipv6: Bool = false) -> [RouteEntry] {
        RouteMessageParser.routes(in: buffer, isIPv6: ipv6) { Self.names[$0] }
    }

    @Test func readsANetworkRouteWithACompressedMask() {
        // 192.0.2.0/24 on en0: the mask is sent as 3 address bytes (sa_len 7).
        let buffer = message(
            index: 6, flags: 0x1 | 0x100_0000, addrs: 0x1 | 0x4,
            body: [
                sockaddr(length: 16, family: AF_INET, header: 4, bytes: [192, 0, 2, 0]),
                sockaddr(length: 7, family: AF_INET, header: 4, bytes: [255, 255, 255]),
            ])
        let entries = parse(buffer)
        #expect(entries.count == 1)
        #expect(entries[0].destination == "192.0.2.0")
        #expect(entries[0].prefixLength == 24)
        #expect(entries[0].destinationWithPrefix == "192.0.2.0/24")
        #expect(entries[0].interfaceName == "en0")
        #expect(entries[0].flags == "UI")
        #expect(entries[0].gateway == nil)
    }

    @Test func readsADefaultRouteAndItsGateway() {
        let buffer = message(
            index: 6, flags: 0x1 | 0x2 | 0x800, addrs: 0x1 | 0x2 | 0x4,
            body: [
                sockaddr(length: 16, family: AF_INET, header: 4, bytes: [0, 0, 0, 0]),
                sockaddr(length: 16, family: AF_INET, header: 4, bytes: [192, 0, 2, 1]),
                sockaddr(length: 0, family: 0, header: 4, bytes: []),
            ])
        let entries = parse(buffer)
        #expect(entries.count == 1)
        #expect(entries[0].isDefault)
        #expect(entries[0].destinationWithPrefix == "default")
        #expect(entries[0].gateway == "192.0.2.1")
        #expect(entries[0].flags == "UGS")
    }

    @Test func readsAHostRouteWithoutAMask() {
        let buffer = message(
            index: 8, flags: 0x1 | 0x4, addrs: 0x1,
            body: [sockaddr(length: 16, family: AF_INET, header: 4, bytes: [10, 250, 10, 1])])
        let entry = parse(buffer)[0]
        #expect(entry.destinationWithPrefix == "10.250.10.1/32")
        #expect(entry.flags == "UH")
    }

    @Test func readsAnIPv6NetworkRoute() {
        var prefix = [UInt8](repeating: 0, count: 16)
        prefix[0] = 0x20
        prefix[1] = 0x01
        prefix[2] = 0x0d
        prefix[3] = 0xb8
        let buffer = message(
            index: 6, flags: 0x1, addrs: 0x1 | 0x4,
            body: [
                sockaddr(length: 28, family: AF_INET6, header: 8, bytes: prefix),
                // A /64 mask: eight 0xFF bytes, the rest dropped (sa_len 16).
                sockaddr(length: 16, family: AF_INET6, header: 8, bytes: [UInt8](repeating: 0xFF, count: 8)),
            ])
        let entry = parse(buffer, ipv6: true)[0]
        #expect(entry.destinationWithPrefix == "2001:db8::/64")
        #expect(entry.isIPv6)
    }

    @Test func skipsMessagesWithoutADestinationOrAKnownInterface() {
        let noAddress = message(index: 6, flags: 0x1, addrs: 0, body: [])
        let unknown = message(
            index: 99, flags: 0x1, addrs: 0x1,
            body: [sockaddr(length: 16, family: AF_INET, header: 4, bytes: [1, 2, 3, 4])])
        #expect(parse(noAddress + unknown).isEmpty)
    }

    @Test func liveTableHasARouteOrIsEmptyWithoutCrashing() {
        let entries = RouteCollector.allRoutes()
        for entry in entries { #expect(!entry.interfaceName.isEmpty) }
    }
}
