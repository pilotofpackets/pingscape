import Darwin
import Testing

@testable import NetKit

/// Builds routing messages byte by byte, the way `sysctl NET_RT_DUMP` returns them.
private enum RouteFixture {
    static func ipv4(_ octets: [UInt8]) -> [UInt8] {
        [16, UInt8(AF_INET), 0, 0] + octets + [UInt8](repeating: 0, count: 8)
    }

    static func ipv6(_ bytes: [UInt8]) -> [UInt8] {
        [28, UInt8(AF_INET6), 0, 0, 0, 0, 0, 0] + bytes + [0, 0, 0, 0]
    }

    static func message(index: Int, flags: Int32, addresses: [[UInt8]]) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: RouteMessageParser.headerSize)
        let body = addresses.flatMap { $0 }
        let length = header.count + body.count
        header[0] = UInt8(length & 0xFF)
        header[1] = UInt8(length >> 8)
        header[4] = UInt8(index & 0xFF)
        header[5] = UInt8(index >> 8)
        for byte in 0..<4 { header[8 + byte] = UInt8((UInt32(bitPattern: flags) >> (8 * UInt32(byte))) & 0xFF) }
        // Destination, plus gateway if a second address is given.
        let addrs: Int32 = addresses.count > 1 ? 0x3 : 0x1
        for byte in 0..<4 { header[12 + byte] = UInt8((UInt32(bitPattern: addrs) >> (8 * UInt32(byte))) & 0xFF) }
        return header + body
    }

    static let up = RouteMessageParser.flagUp
    static let gateway = RouteMessageParser.flagGateway
    static let scoped = RouteMessageParser.flagInterfaceScope
    static let host = RouteMessageParser.flagHost
    static let names: [Int: String] = [6: "en0", 8: "utun4", 12: "pdp_ip0"]

    static func parse(_ buffer: [UInt8], ipv6: Bool = false) -> [DefaultRoute] {
        RouteMessageParser.defaultRoutes(in: buffer, isIPv6: ipv6) { names[$0] }
    }
}

@Suite("Routing table parser")
struct RouteMessageParserTests {
    @Test func readsAnIPv4DefaultRouteWithGateway() {
        let buffer = RouteFixture.message(
            index: 6, flags: RouteFixture.up | RouteFixture.gateway,
            addresses: [RouteFixture.ipv4([0, 0, 0, 0]), RouteFixture.ipv4([192, 168, 178, 1])])
        #expect(
            RouteFixture.parse(buffer)
                == [DefaultRoute(interfaceName: "en0", gateway: "192.168.178.1", isIPv6: false, isActive: true)])
    }

    @Test func marksInterfaceBoundRoutesAsInactive() {
        let buffer = RouteFixture.message(
            index: 6, flags: RouteFixture.up | RouteFixture.gateway | RouteFixture.scoped,
            addresses: [RouteFixture.ipv4([0, 0, 0, 0]), RouteFixture.ipv4([192, 168, 178, 1])])
        #expect(RouteFixture.parse(buffer).first?.isActive == false)
    }

    @Test func readsAPointToPointDefaultRouteWithoutGateway() {
        let buffer = RouteFixture.message(
            index: 8, flags: RouteFixture.up, addresses: [RouteFixture.ipv4([0, 0, 0, 0])])
        #expect(
            RouteFixture.parse(buffer)
                == [DefaultRoute(interfaceName: "utun4", gateway: nil, isIPv6: false, isActive: true)])
    }

    @Test func ignoresOtherDestinationsHostRoutesAndDownRoutes() {
        let other = RouteFixture.message(
            index: 6, flags: RouteFixture.up | RouteFixture.gateway,
            addresses: [RouteFixture.ipv4([10, 0, 0, 0]), RouteFixture.ipv4([192, 168, 178, 1])])
        let host = RouteFixture.message(
            index: 6, flags: RouteFixture.up | RouteFixture.host,
            addresses: [RouteFixture.ipv4([0, 0, 0, 0])])
        let down = RouteFixture.message(
            index: 6, flags: RouteFixture.gateway,
            addresses: [RouteFixture.ipv4([0, 0, 0, 0]), RouteFixture.ipv4([192, 168, 178, 1])])
        #expect(RouteFixture.parse(other + host + down).isEmpty)
    }

    @Test func clearsTheScopeStoredInsideALinkLocalGateway() {
        // The kernel writes the interface index into bytes 2 and 3 (fe80:0006::1).
        let linkLocal: [UInt8] = [0xFE, 0x80, 0x00, 0x06] + [UInt8](repeating: 0, count: 11) + [1]
        let buffer = RouteFixture.message(
            index: 6, flags: RouteFixture.up | RouteFixture.gateway,
            addresses: [RouteFixture.ipv6([UInt8](repeating: 0, count: 16)), RouteFixture.ipv6(linkLocal)])
        #expect(
            RouteFixture.parse(buffer, ipv6: true)
                == [DefaultRoute(interfaceName: "en0", gateway: "fe80::1", isIPv6: true, isActive: true)])
    }

    @Test func readsSeveralMessagesAndSkipsUnknownInterfaces() {
        let wifi = RouteFixture.message(
            index: 6, flags: RouteFixture.up | RouteFixture.gateway,
            addresses: [RouteFixture.ipv4([0, 0, 0, 0]), RouteFixture.ipv4([192, 168, 178, 1])])
        let unknown = RouteFixture.message(
            index: 99, flags: RouteFixture.up, addresses: [RouteFixture.ipv4([0, 0, 0, 0])])
        let cellular = RouteFixture.message(
            index: 12, flags: RouteFixture.up | RouteFixture.scoped,
            addresses: [RouteFixture.ipv4([0, 0, 0, 0])])
        #expect(RouteFixture.parse(wifi + unknown + cellular).map(\.interfaceName) == ["en0", "pdp_ip0"])
    }

    @Test func survivesTruncatedInput() {
        let buffer = RouteFixture.message(
            index: 6, flags: RouteFixture.up | RouteFixture.gateway,
            addresses: [RouteFixture.ipv4([0, 0, 0, 0]), RouteFixture.ipv4([192, 168, 178, 1])])
        for cut in 0..<buffer.count {
            _ = RouteFixture.parse(Array(buffer[..<cut]))
        }
        #expect(RouteFixture.parse([]).isEmpty)
    }
}
