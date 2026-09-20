import Testing

@testable import NetKit

@Suite("IPv4 helpers")
struct IPv4Tests {
    @Test func roundTripsDottedQuads() {
        #expect(IPv4.toInt("192.168.178.42") == 0xC0A8_B22A)
        #expect(IPv4.toString(0xC0A8_B22A) == "192.168.178.42")
    }

    @Test(arguments: ["", "1.2.3", "1.2.3.4.5", "256.1.1.1", "a.b.c.d", "1..2.3"])
    func rejectsMalformedAddresses(_ text: String) {
        #expect(IPv4.toInt(text) == nil)
    }

    @Test func convertsNetmaskAndPrefix() {
        #expect(IPv4.prefix(fromNetmask: "255.255.255.0") == 24)
        #expect(IPv4.prefix(fromNetmask: "255.255.255.255") == 32)
        #expect(IPv4.prefix(fromNetmask: "0.0.0.0") == 0)
        #expect(IPv4.prefix(fromNetmask: "255.0.255.0") == nil)
        #expect(IPv4.netmask(fromPrefix: 24) == "255.255.255.0")
        #expect(IPv4.netmask(fromPrefix: 22) == "255.255.252.0")
        #expect(IPv4.netmask(fromPrefix: 0) == "0.0.0.0")
        #expect(IPv4.netmask(fromPrefix: 32) == "255.255.255.255")
    }

    @Test func describesANetworkFromAnyHostAddress() throws {
        let range = try #require(IPv4Range(ip: "192.168.178.42", prefix: 24))
        #expect(range.networkAddress == "192.168.178.0")
        #expect(range.broadcast == "192.168.178.255")
        #expect(range.hostCount == 254)
        #expect(range.description == "192.168.178.0/24")
    }

    @Test func listsHostsWithoutNetworkAndBroadcast() throws {
        let range = try #require(IPv4Range(ip: "10.0.0.7", prefix: 29))
        #expect(range.hosts() == (1...6).map { "10.0.0.\($0)" })
    }

    @Test func capsLargeNetworks() throws {
        let range = try #require(IPv4Range(ip: "10.1.2.3", prefix: 8))
        #expect(range.hostCount == 16_777_214)
        #expect(range.hosts(limit: 1024).count == 1024)
        #expect(range.hosts(limit: 1024).first == "10.0.0.1")
    }

    @Test func treatsPointToPointNetworksAsSingleHost() throws {
        let range = try #require(IPv4Range(ip: "10.250.10.1", prefix: 32))
        #expect(range.hostCount == 1)
        #expect(range.hosts() == ["10.250.10.1"])
    }
}
