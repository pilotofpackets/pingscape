import Testing

@testable import NetKit

@Suite("Interface classification")
struct InterfaceKindTests {
    @Test(arguments: [
        ("lo0", InterfaceKind.loopback),
        ("en0", .wifi),
        ("en1", .ethernet),
        ("ap1", .hotspot),
        ("bridge100", .hotspot),
        ("pdp_ip0", .cellular),
        ("pdp_ip3", .cellular),
        ("ipsec0", .ipsec),
        ("utun4", .tunnel),
        ("ppp0", .tunnel),
        ("awdl0", .other),
        ("llw0", .other),
    ])
    func classifiesByName(_ name: String, _ expected: InterfaceKind) {
        #expect(InterfaceKind(interfaceName: name) == expected)
    }

    @Test func detectsUsableAddresses() {
        #expect(InterfaceAddress(ip: "192.168.1.5", isIPv6: false).isUsable)
        #expect(InterfaceAddress(ip: "2001:db8::1", isIPv6: true).isUsable)
        #expect(!InterfaceAddress(ip: "fe80::1", isIPv6: true).isUsable)
        #expect(!InterfaceAddress(ip: "169.254.10.10", isIPv6: false).isUsable)
        #expect(!InterfaceAddress(ip: "127.0.0.1", isIPv6: false).isUsable)
        #expect(!InterfaceAddress(ip: "::1", isIPv6: true).isUsable)
        #expect(!InterfaceAddress(ip: "", isIPv6: false).isUsable)
    }
}
