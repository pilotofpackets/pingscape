import Testing

@testable import NetKit

@Suite("MAC addresses and vendors")
struct MACAddressTests {
    @Test func padsTheShortBSSIDiOSReturns() {
        #expect(MACAddress.canonical("0:11:22:a:b:c") == "00:11:22:0A:0B:0C")
        #expect(MACAddress.canonical("3c:a6:2f:1b:d3:22") == "3C:A6:2F:1B:D3:22")
    }

    @Test func readsOtherSpellings() {
        #expect(MACAddress.canonical("00-11-22-AA-BB-CC") == "00:11:22:AA:BB:CC")
        #expect(MACAddress.canonical("0011.22aa.bbcc") == "00:11:22:AA:BB:CC")
        #expect(MACAddress.canonical("001122AABBCC") == "00:11:22:AA:BB:CC")
    }

    @Test(arguments: ["", "00:11:22", "zz:11:22:33:44:55", "00:11:22:33:44:55:66"])
    func rejectsNonMACs(_ text: String) {
        #expect(MACAddress.canonical(text) == nil)
    }

    @Test func detectsLocallyAdministeredAddresses() {
        #expect(MACAddress.isLocallyAdministered("02:00:00:00:00:01"))
        #expect(MACAddress.isLocallyAdministered("DA:A1:19:00:00:00"))
        #expect(!MACAddress.isLocallyAdministered("3C:A6:2F:1B:D3:22"))
        #expect(!MACAddress.isLocallyAdministered("nonsense"))
    }

    @Test func extractsThePrefix() {
        #expect(MACAddress.prefix("3c:a6:2f:1b:d3:22") == "3CA62F")
    }
}

@Suite("OUI registry")
struct OUIRegistryTests {
    private let registry = OUIRegistry(
        text: "3CA62F\tAVM GmbH\n000001\tXEROX\r\nbadline\nABCDEFG\ttoo long\n")

    @Test func parsesTabSeparatedLines() {
        #expect(registry.count == 2)
    }

    @Test func looksUpTheVendorOfAnEndDevice() {
        #expect(registry.vendor(forMAC: "3c:a6:2f:00:00:01") == "AVM GmbH")
        #expect(registry.vendor(forMAC: "aa:bb:cc:dd:ee:ff") == nil)
    }

    @Test func doesNotReadAVendorIntoARandomAddress() {
        // Locally administered bit set: a private address, not a real prefix.
        #expect(registry.vendor(forMAC: "3E:A6:2F:00:00:01") == nil)
    }

    @Test func findsTheVendorOfAGuestNetworkBSSID() {
        // The access point sets the locally administered bit on the extra BSSID.
        #expect(registry.vendor(forBSSID: "3E:A6:2F:1B:D3:22") == "AVM GmbH")
        #expect(registry.vendor(forBSSID: "3C:A6:2F:1B:D3:22") == "AVM GmbH")
        #expect(registry.vendor(forBSSID: "02:00:00:00:00:00") == nil)
    }
}
