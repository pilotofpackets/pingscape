import Foundation
import Testing

@testable import NetKit

@Suite("Reports")
struct ReportTests {
    private let sections = [
        ReportSection(
            title: "Connection",
            rows: [
                ReportRow(label: "IP address", value: "192.0.2.42", isSensitive: true),
                ReportRow(label: "DNS servers", value: "192.0.2.1\n192.0.2.2", isSensitive: true),
                ReportRow(label: "Proxy", value: "Off", isSensitive: false),
                ReportRow(label: "Empty", value: "", isSensitive: false),
            ]),
        ReportSection(title: "Nothing", rows: [ReportRow(label: "x", value: "", isSensitive: false)]),
        ReportSection(title: "Wi-Fi", rows: [ReportRow(label: "Name (SSID)", value: "HomeNet", isSensitive: true)]),
    ]

    @Test func writesHeaderAndSectionsWithoutEmptyRows() {
        let text = ReportFormatter.text(header: ["Pingscape 1.0 (12)", "iPhone 16 · iOS 26.0"], sections: sections, masked: false)
        #expect(
            text == """
                Pingscape 1.0 (12)
                iPhone 16 · iOS 26.0

                CONNECTION
                IP address: 192.0.2.42
                DNS servers: 192.0.2.1, 192.0.2.2
                Proxy: Off

                WI-FI
                Name (SSID): HomeNet
                """)
    }

    @Test func replacesSensitiveValuesWhileHidden() {
        let text = ReportFormatter.text(header: [], sections: sections, masked: true)
        #expect(!text.contains("192.0.2") && !text.contains("HomeNet"))
        #expect(text.contains("IP address: \(ReportFormatter.placeholder)"))
        #expect(text.contains("Proxy: Off"))
    }

    @Test func copiesASingleSectionWithItsHeading() {
        #expect(ReportFormatter.text(of: sections[2], masked: false) == "WI-FI\nName (SSID): HomeNet")
        #expect(ReportFormatter.text(of: sections[2], masked: true) == "WI-FI\nName (SSID): \(ReportFormatter.placeholder)")
    }

    @Test func jsonDropsEmptyRowsAndSections() throws {
        let data = try ReportFormatter.json(header: ["Pingscape 1.0 (12)"], sections: sections, masked: false)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("\"Nothing\""))
        #expect(!text.contains("\"Empty\""))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(decoded["header"] as? [String] == ["Pingscape 1.0 (12)"])
        let jsonSections = try #require(decoded["sections"] as? [[String: Any]])
        #expect(jsonSections.count == 2)
        #expect(jsonSections[0]["title"] as? String == "Connection")
    }

    @Test func jsonKeepsLineBreaksInAMultiLineValue() throws {
        let data = try ReportFormatter.json(header: [], sections: sections, masked: false)
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require((decoded["sections"] as? [[String: Any]])?.first?["rows"] as? [[String: String]])
        #expect(rows[1]["value"] == "192.0.2.1\n192.0.2.2")
    }

    @Test func jsonReplacesSensitiveValuesWhileHidden() throws {
        let data = try ReportFormatter.json(header: [], sections: sections, masked: true)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("192.0.2") && !text.contains("HomeNet"))
        #expect(text.contains(ReportFormatter.placeholder))
        #expect(text.contains("\"Off\""))
    }

    private let devices = [
        LANDevice(ip: "192.0.2.40", latencyMilliseconds: 4, answeredPing: true, hostname: "tv.example",
                  services: [LANService(type: "_airplay._tcp", name: "Living Room, TV"), LANService(type: "_raop._tcp", name: "x")]),
        LANDevice(ip: "192.0.2.52"),
    ]

    @Test func writesOneLinePerDevice() {
        #expect(LANReport.text(devices, masked: false) == "192.0.2.40 · Living Room, TV · airplay, raop · 4 ms\n192.0.2.52")
        let masked = LANReport.text(devices, masked: true)
        #expect(!masked.contains("192.0.2") && !masked.contains("Living Room"))
        #expect(masked.contains("airplay, raop · 4 ms"))
    }

    @Test func writesCSVWithQuoting() {
        #expect(
            LANReport.csv(devices, masked: false)
                == "ip,name,services,latency_ms\n192.0.2.40,\"Living Room, TV\",airplay raop,4.0\n192.0.2.52,,,\n")
        #expect(!LANReport.csv(devices, masked: true).contains("192.0.2"))
    }

    @Test func readsTheNAT64Prefixes() {
        var wellKnown = [UInt8](repeating: 0, count: 16)
        wellKnown[1] = 0x64
        wellKnown[2] = 0xFF
        wellKnown[3] = 0x9B
        wellKnown.replaceSubrange(12..<16, with: [192, 0, 0, 170])
        #expect(NAT64Collector.prefix(fromSynthesized: wellKnown) == "64:ff9b::/96")
        var other = wellKnown
        other[15] = 5
        #expect(NAT64Collector.prefix(fromSynthesized: other) == nil)
        #expect(NAT64Collector.prefix(fromSynthesized: [1, 2, 3]) == nil)
    }

    /// Seen on an iPhone in a plain IPv4 Wi-Fi: the resolver answered
    /// `::ffff:192.0.0.170`, which is no NAT64 prefix.
    @Test func ignoresIPv4MappedAnswers() {
        var mapped = [UInt8](repeating: 0, count: 16)
        mapped[10] = 0xFF
        mapped[11] = 0xFF
        mapped.replaceSubrange(12..<16, with: [192, 0, 0, 170])
        #expect(NAT64Collector.prefix(fromSynthesized: mapped) == nil)
    }
}

@Suite("Raw text in reports")
struct PreformattedReportTests {
    @Test func keepsTheLinesOfRawText() {
        let section = ReportSection(
            title: "whois.example.net",
            rows: [ReportRow(label: "", value: "domain: COM\nrefer: whois.example", isSensitive: false, isPreformatted: true)])
        #expect(ReportFormatter.text(of: section, masked: false) == "WHOIS.EXAMPLE.NET\ndomain: COM\nrefer: whois.example")
    }
}
