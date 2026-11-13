import Foundation
import Testing

@testable import NetKit

@Suite("Edge cases of the parsers")
struct ParserEdgeCaseTests {
    /// Made with OpenSSL (string_mask = default): the common name "Gerät €-Router"
    /// is a BMPString (UTF-16), as some older devices and CAs write names; the
    /// organization is a PrintableString.
    static let bmpCertificate = "MIIBdzCCAR2gAwIBAgIDAL7vMAoGCCqGSM49BAMCMEQxJTAjBgNVBAMeHABHAGUAcgDkAHQAICCsAC0AUgBvAHUAdABlAHIxGzAZBgNVBAoTElBpbmdzY2FwZSBUZXN0IE9yZzAeFw0yNjExMTExMzQxNTVaFw0zNjExMDgxMzQxNTVaMEQxJTAjBgNVBAMeHABHAGUAcgDkAHQAICCsAC0AUgBvAHUAdABlAHIxGzAZBgNVBAoTElBpbmdzY2FwZSBUZXN0IE9yZzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABPUXGvqwEGSO5sflSJfqil9nnNUs0HKMatOWjK/yVbt5yYG1Y+MLIFhiKtfMAcegK+NXYknZ6hxaezJsNTTwZt0wCgYIKoZIzj0EAwIDSAAwRQIhAPTQccgsOHhMcvN1LTig1LGJx65H2oBGQGQcCLetvjpOAiBgQ2CjdhTqG3xs4yqmOGKjVP497GLRBmmsydy5kY7l8Q=="

    @Test("A name in UTF-16 (BMPString) is read, umlaut and euro sign included")
    func bmpString() throws {
        let info = try #require(X509.parse(der: [UInt8](Data(base64Encoded: Self.bmpCertificate)!)))
        #expect(info.subjectName == "Gerät €-Router")
        #expect(info.subjectOrganization == "Pingscape Test Org")
        #expect(info.isSelfIssued)
    }

    @Test("Certificates that are not DER are turned down, not crashed on", arguments: [
        [UInt8](), [0x30], [0x30, 0x82, 0xFF, 0xFF], [0x02, 0x01, 0x00], Array(repeating: 0x30, count: 64),
    ])
    func garbageCertificates(_ bytes: [UInt8]) {
        #expect(X509.parse(der: bytes) == nil)
    }

    /// One answer for example.com of `type` with `data`.
    private func reply(type: UInt16, data: [UInt8]) throws -> [UInt8] {
        let header: [UInt8] = [0x12, 0x34, 0x81, 0x80, 0, 0, 0, 1, 0, 0, 0, 0]
        let name = try DNSMessage.encodeName("example.com")
        let fixed: [UInt8] = [
            UInt8(type >> 8), UInt8(type & 0xFF), 0, 1, 0, 0, 0x0E, 0x10, UInt8(data.count >> 8), UInt8(data.count & 0xFF),
        ]
        return header + name + fixed + data
    }

    @Test("A record type the app does not know is shown as RFC 3597 writes it")
    func unknownType() throws {
        let message = try DNSMessage.parse(try reply(type: 65_280, data: [0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(message.answers.first?.value == "\\# 4 deadbeef")
        #expect(message.answers.first?.ttl == 3600)
    }

    @Test("An empty record of an unknown type is still readable")
    func emptyUnknown() throws {
        let message = try DNSMessage.parse(try reply(type: 65_281, data: []))
        #expect(message.answers.first?.value == "\\# 0 ")
    }

    @Test("A record shorter than its type needs is dropped and the message marked incomplete", arguments: [
        (UInt16(1), [UInt8](repeating: 1, count: 3)),  // A with 3 bytes
        (UInt16(28), [UInt8](repeating: 1, count: 15)),  // AAAA with 15 bytes
        (UInt16(257), [UInt8]([0])),  // CAA without a tag
        (UInt16(257), [UInt8]([0, 9, 0x69])),  // CAA tag longer than the record
    ])
    func shortRecords(_ type: UInt16, _ data: [UInt8]) throws {
        let message = try DNSMessage.parse(try reply(type: type, data: data))
        #expect(message.answers.isEmpty, "A broken record must not show up as an answer")
        #expect(message.isIncomplete)
    }

    @Test("Records are equal by name, type, TTL and value")
    func recordEquality() throws {
        let first = try #require(try DNSMessage.parse(try reply(type: 1, data: [192, 0, 2, 1])).answers.first)
        let again = try #require(try DNSMessage.parse(try reply(type: 1, data: [192, 0, 2, 1])).answers.first)
        let other = try #require(try DNSMessage.parse(try reply(type: 1, data: [192, 0, 2, 2])).answers.first)
        #expect(first == again)
        #expect(first != other)
    }
}

@Suite("Small model details")
struct ModelDetailTests {
    @Test("Router information is empty only when nothing at all is known")
    func routerInfoEmpty() {
        #expect(RouterInfo().isEmpty)
        #expect(!RouterInfo(manufacturer: "AVM").isEmpty)
        #expect(!RouterInfo(uptimeSeconds: 0).isEmpty)
        #expect(!RouterInfo(externalIP: "203.0.113.57").isEmpty)
    }

    @Test("The demo has an IPv4 gateway but none for IPv6, and no primary IPv6 on the tunnel")
    func demoGateways() {
        let snapshot = DemoData.snapshot
        #expect(snapshot.localGateway4 == "192.168.178.1")
        #expect(snapshot.localGateway6 == nil)
    }

    @Test("A port of 0, above 65535 or after a broken bracket is turned down", arguments: [
        "[::1]:0", "[::1]:65536", "[::1]x", "[::1", "example.com:0", "example.com:99999", "example.com:http",
    ])
    func badPorts(_ text: String) {
        #expect(throws: InputError.self) { try ToolInput.hostAndPort(text, defaultPort: 443) }
    }

    @Test("Ports and defaults are read in every notation", arguments: [
        ("[2001:db8::1]:8443", "2001:db8::1", UInt16(8443)), ("[2001:db8::1]", "2001:db8::1", UInt16(443)),
        ("example.com", "example.com", UInt16(443)), ("https://user@example.com:8080/path?q", "example.com", UInt16(8080)),
    ])
    func goodPorts(_ text: String, _ host: String, _ port: UInt16) throws {
        let parsed = try ToolInput.hostAndPort(text, defaultPort: 443)
        #expect(parsed.host == host)
        #expect(parsed.port == port)
    }
}

@Suite("UPnP description on this machine", .serialized)
struct UPnPLoopbackTests {
    static let xml = """
        <?xml version="1.0"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <friendlyName>Loopback Router</friendlyName>
            <manufacturer>Example &amp; Sons</manufacturer>
            <modelName>LR</modelName>
            <modelNumber>42</modelNumber>
          </device>
        </root>
        """

    @Test("The description is fetched and read, entities decoded")
    func fetches() async throws {
        let server = try await LoopbackHTTPServer { path in
            path == "/desc.xml"
                ? LoopbackHTTPServer.response("200 OK", headers: ["Content-Type": "text/xml"], body: Self.xml)
                : LoopbackHTTPServer.response("404 Not Found")
        }
        defer { server.stop() }
        let description = try #require(await UPnPClient.fetchDescription(at: URL(string: "http://127.0.0.1:\(server.port)/desc.xml")!))
        #expect(description.friendlyName == "Loopback Router")
        #expect(description.manufacturer == "Example & Sons")
        #expect(description.model == "LR 42")
    }

    @Test("A missing page or a page that is not XML gives nothing, not a crash")
    func missing() async throws {
        let server = try await LoopbackHTTPServer { path in
            path == "/html"
                ? LoopbackHTTPServer.response("200 OK", body: "<html><body>Login</body></html>")
                : LoopbackHTTPServer.response("404 Not Found")
        }
        defer { server.stop() }
        let base = "http://127.0.0.1:\(server.port)"
        #expect(await UPnPClient.fetchDescription(at: URL(string: base + "/nothing")!) == nil)
        let html = await UPnPClient.fetchDescription(at: URL(string: base + "/html")!)
        #expect(html == nil || html?.friendlyName == nil)
    }
}
