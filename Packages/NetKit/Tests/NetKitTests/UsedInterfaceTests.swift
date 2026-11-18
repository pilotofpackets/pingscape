import Darwin
import Foundation
import Testing

@testable import NetKit

/// The interface a test really ran on, read from the socket that carried it.
@Suite("Used interface")
struct UsedInterfaceTests {
    private let loopback = ResolvedAddress(literal: "127.0.0.1")!
    private let loopbackIndex = if_nametoindex("lo0")

    /// One control message as `recvmsg` lays it out: header, padded to 4
    /// bytes, then the data.
    private func controlMessage(level: Int32, type: Int32, data: [UInt8]) -> [UInt8] {
        let headerSize = (MemoryLayout<cmsghdr>.size + 3) & ~3
        var header = cmsghdr(cmsg_len: socklen_t(headerSize + data.count), cmsg_level: level, cmsg_type: type)
        var bytes = withUnsafeBytes(of: &header) { Array($0) }
        bytes += [UInt8](repeating: 0, count: headerSize - bytes.count) + data
        while bytes.count % 4 != 0 { bytes.append(0) }
        return bytes
    }

    @Test func readsTheIPv4ArrivalInterface() {
        // sockaddr_dl: length, family, then the interface index.
        let index = UInt16(loopbackIndex)
        var link: [UInt8] = [20, UInt8(AF_LINK), UInt8(index & 0xFF), UInt8(index >> 8)]
        link += [UInt8](repeating: 0, count: 16)
        // A destination address first, as with IP_RECVDSTADDR, which is skipped.
        let control = controlMessage(level: IPPROTO_IP, type: IP_RECVDSTADDR, data: [127, 0, 0, 1])
            + controlMessage(level: IPPROTO_IP, type: IP_RECVIF, data: link)
        let name = control.withUnsafeBytes { UsedInterface.arrivalInterface(control: $0, length: control.count) }
        #expect(name == "lo0")
    }

    @Test func readsTheIPv6ArrivalInterface() {
        var info = in6_pktinfo()
        info.ipi6_ifindex = loopbackIndex
        let data = withUnsafeBytes(of: &info) { Array($0) }
        let control = controlMessage(level: IPPROTO_IPV6, type: UsedInterface.ipv6PacketInfo, data: data)
        let name = control.withUnsafeBytes { UsedInterface.arrivalInterface(control: $0, length: control.count) }
        #expect(name == "lo0")
    }

    @Test func namesNothingWithoutAControlMessage() {
        let control = controlMessage(level: IPPROTO_IP, type: IP_RECVDSTADDR, data: [127, 0, 0, 1])
        #expect(control.withUnsafeBytes { UsedInterface.arrivalInterface(control: $0, length: control.count) } == nil)
        #expect([UInt8]().withUnsafeBytes { UsedInterface.arrivalInterface(control: $0, length: 0) } == nil)
        // A length that claims more than the buffer holds is not read.
        var broken = control
        broken[0] = 200
        #expect(broken.withUnsafeBytes { UsedInterface.arrivalInterface(control: $0, length: broken.count) } == nil)
    }

    @Test func findsTheInterfaceHoldingAnAddress() {
        #expect(UsedInterface.holding(localAddress: "127.0.0.1") == "lo0")
        // TEST-NET-1 belongs to no interface.
        #expect(UsedInterface.holding(localAddress: "192.0.2.1") == nil)
    }

    @Test func aConnectedSocketNamesItsInterface() throws {
        let socket = try POSIXSocket(family: AF_INET, type: SOCK_DGRAM)
        let status = loopback.withSockaddr(port: 9) { sa, length in Darwin.connect(socket.fd, sa, length) }
        #expect(status == 0)
        #expect(socket.localAddressText() == "127.0.0.1")
        #expect(socket.usedInterface() == "lo0")
    }

    @Test func anUnconnectedSocketNamesNothing() throws {
        let socket = try POSIXSocket(family: AF_INET, type: SOCK_DGRAM)
        #expect(socket.localAddressText() == nil)
        #expect(socket.usedInterface() == nil)
    }

    // Needs an ICMP datagram socket, which a locked-down CI machine may not give.
    @Test(.enabled(if: ICMPEcho.isAvailable())) func pingRepliesNameTheLoopback() async {
        var settings = PingSettings()
        settings.intervalSeconds = 0.05
        var via: [Int: String] = [:]
        var replies = 0
        var events = 0
        for await event in PingTool.run(address: loopback, settings: settings) {
            events += 1
            if case .via(let sequence, let interface) = event { via[sequence] = interface }
            if case .reply(let sequence, _, _, _) = event {
                // The interface comes before the reply it belongs to.
                #expect(via[sequence] == "lo0")
                replies += 1
            }
            if replies == 2 || events > 30 { break }
        }
        #expect(replies == 2)
    }

    // Needs an ICMP datagram socket, which a locked-down CI machine may not give.
    @Test(.enabled(if: ICMPEcho.isAvailable())) func tracerouteNamesTheLoopbackOnce() async {
        var via: [String] = []
        for await event in TracerouteTool.run(
            address: loopback, settings: TracerouteSettings(probesPerHop: 3, timeoutSeconds: 1, resolveNames: false))
        {
            if case .via(let interface) = event { via.append(interface) }
        }
        #expect(via == ["lo0"])
    }

    @Test func tcpPingNamesTheLoopback() async throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(listener) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ready = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, length) == 0 && listen(listener, 4) == 0 && getsockname(listener, $0, &length) == 0
            }
        }
        #expect(ready)
        let outcome = try await TCPProbe.once(
            address: loopback, port: UInt16(bigEndian: address.sin_port), timeoutMilliseconds: 1000)
        if case .open = outcome.result {} else { Issue.record("Expected an open port, got \(outcome.result)") }
        #expect(outcome.interface == "lo0")
    }
}
