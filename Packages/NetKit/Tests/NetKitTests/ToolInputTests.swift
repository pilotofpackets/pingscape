import Testing

@testable import NetKit

@Suite("Tool input")
struct ToolInputTests {
    @Test(arguments: [
        ("example.com", "example.com"),
        ("  Example.COM.  ", "example.com"),
        ("https://user:pw@example.com:8443/a/b?c=d#e", "example.com"),
        ("http://192.0.2.1/index.html", "192.0.2.1"),
        ("[2001:db8::1]", "2001:db8::1"),
        ("2001:db8::1", "2001:db8::1"),
        ("fe80::1%en0", "fe80::1"),
        ("müller.de", "xn--mller-kva.de"),
    ])
    func cleansHosts(input: String, expected: String) throws {
        #expect(try ToolInput.host(input) == expected)
    }

    @Test(arguments: ["", "   ", "exa mple.com", "-a.example", "a..example", "999.1.1.1", "1.2.3", "ex@mple.com:"])
    func rejectsBrokenHosts(_ input: String) {
        #expect(throws: InputError.self) { try ToolInput.host(input) }
    }

    @Test func allowsUnderscoresOnlyForDNS() throws {
        #expect(try ToolInput.host("_sip._tcp.example.com", allowUnderscore: true) == "_sip._tcp.example.com")
        #expect(throws: InputError.invalidHost) { try ToolInput.host("_sip._tcp.example.com") }
    }

    @Test func splitsHostAndPort() throws {
        #expect(try ToolInput.hostAndPort("example.com:8443", defaultPort: 443) == ("example.com", 8443))
        #expect(try ToolInput.hostAndPort("example.com", defaultPort: 443) == ("example.com", 443))
        #expect(try ToolInput.hostAndPort("[2001:db8::1]:993", defaultPort: 443) == ("2001:db8::1", 993))
        #expect(try ToolInput.hostAndPort("2001:db8::1", defaultPort: 443) == ("2001:db8::1", 443))
        #expect(throws: InputError.invalidPort) { try ToolInput.hostAndPort("example.com:0", defaultPort: 443) }
        #expect(throws: InputError.invalidPort) { try ToolInput.hostAndPort("example.com:http", defaultPort: 443) }
    }
}

@Suite("Port lists")
struct PortListTests {
    @Test func parsesListsAndRanges() throws {
        #expect(try PortList.parse("22,80,443") == [22, 80, 443])
        #expect(try PortList.parse("8000-8003, 22 80") == [22, 80, 8000, 8001, 8002, 8003])
        #expect(try PortList.parse("443,443,80") == [80, 443])
        #expect(try PortList.parse("8003-8000") == [8000, 8001, 8002, 8003])
    }

    @Test(arguments: ["", "abc", "0", "65536", "80-", "-80", "1-2-3", "80,,x"])
    func rejectsBrokenLists(_ text: String) {
        #expect(throws: InputError.self) { try PortList.parse(text) }
    }

    @Test func limitsTheNumberOfPorts() throws {
        #expect(try PortList.parse("1-5000").count == 5000)
        #expect(throws: InputError.tooManyPorts) { try PortList.parse("1-5001") }
        #expect(throws: InputError.tooManyPorts) { try PortList.parse("1-3000,4000-6000") }
    }

    @Test func namesOnlyPortsWithAFixedAssignment() {
        #expect(PortNames.name(for: 22) == "SSH")
        #expect(PortNames.name(for: 443) == "HTTPS")
        // Popular for one product, not assigned: no name.
        for port in [3000, 4444, 8123, 32400, 62078, 51820] {
            #expect(PortNames.name(for: port) == nil)
        }
        #expect(PortScanner.commonPorts.count == 67)
    }
}

@Suite("Subnet calculator")
struct SubnetCalculatorTests {
    @Test func calculatesASlash24() throws {
        let info = try SubnetInfo("192.0.2.42/24")
        #expect(info.network == "192.0.2.0")
        #expect(info.mask == "255.255.255.0")
        #expect(info.wildcard == "0.0.0.255")
        #expect(info.broadcast == "192.0.2.255")
        #expect(info.firstHost == "192.0.2.1")
        #expect(info.lastHost == "192.0.2.254")
        #expect(info.hostCount == 254)
    }

    @Test func acceptsAMaskInsteadOfAPrefix() throws {
        #expect(try SubnetInfo("10.1.2.3 255.255.252.0") == SubnetInfo("10.1.2.3/22"))
        #expect(try SubnetInfo("10.1.2.3/255.255.252.0").network == "10.1.0.0")
    }

    @Test func handlesPointToPointNetworks() throws {
        let pair = try SubnetInfo("192.0.2.4/31")
        #expect(pair.hostCount == 2)
        #expect(pair.broadcast == nil)
        #expect(pair.firstHost == "192.0.2.4")
        #expect(pair.lastHost == "192.0.2.5")
        let single = try SubnetInfo("192.0.2.9/32")
        #expect(single.hostCount == 1)
        #expect(single.firstHost == "192.0.2.9")
        #expect(single.lastHost == "192.0.2.9")
        #expect(single.broadcast == nil)
    }

    @Test func handlesTheExtremes() throws {
        let all = try SubnetInfo("0.0.0.0/0")
        #expect(all.hostCount == 4_294_967_294)
        #expect(all.broadcast == "255.255.255.255")
        #expect(try SubnetInfo("192.0.2.1/30").hostCount == 2)
    }

    @Test(arguments: ["", "192.0.2.1", "192.0.2.1/33", "192.0.2.1/x", "192.0.2/24", "192.0.2.1 255.0.255.0"])
    func rejectsBrokenInput(_ text: String) {
        #expect(throws: InputError.invalidSubnet) { try SubnetInfo(text) }
    }
}

@Suite("OUI lookup")
struct OUILookupTests {
    private let registry = OUIRegistry(table: ["3CA62F": "AVM GmbH"])

    @Test(arguments: ["3C:A6:2F:1B:00:1F", "3c-a6-2f-1b-00-1f", "3ca6.2f1b.001f", "3CA62F1B001F", "3C:A6:2F", "3ca62f"])
    func findsTheVendorInEverySpelling(_ input: String) throws {
        #expect(try registry.lookup(input) == .vendor("AVM GmbH"))
    }

    @Test func reportsRandomAddressesWithoutAVendor() throws {
        // The locally administered bit (0x02 in the first byte) is set.
        #expect(try registry.lookup("3E:A6:2F:1B:00:1F") == .locallyAdministered)
    }

    @Test func reportsUnknownPrefixes() throws {
        #expect(try registry.lookup("00:11:22:33:44:55") == .notFound)
    }

    @Test(arguments: ["", "3C:A6", "3C:A6:2F:1B:00", "gg:gg:gg", "3C:A6:2F:1B:00:1F:22"])
    func rejectsBrokenInput(_ input: String) {
        #expect(throws: InputError.self) { try registry.lookup(input) }
    }
}

@Suite("Local addresses")
struct LocalAddressTests {
    @Test(arguments: ["10.0.0.1", "172.16.0.9", "172.31.255.1", "192.168.178.1", "169.254.1.1", "127.0.0.1", "100.72.31.14", "::1", "fe80::1", "fd12:3456::1", "fc00::1"])
    func recognizesLocalAddresses(_ text: String) throws {
        #expect(try #require(ResolvedAddress(literal: text)).isLocal)
    }

    @Test(arguments: ["1.1.1.1", "8.8.8.8", "172.32.0.1", "172.15.0.1", "192.169.0.1", "100.128.0.1", "203.0.113.5", "2606:4700:4700::1111", "2001:db8::1"])
    func recognizesPublicAddresses(_ text: String) throws {
        #expect(try #require(ResolvedAddress(literal: text)).isLocal == false)
    }
}
