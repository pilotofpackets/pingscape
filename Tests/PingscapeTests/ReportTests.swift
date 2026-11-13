import Foundation
import NetKit
import Testing

@testable import Pingscape

@MainActor
@Suite("Reports", .serialized)
struct AppReportTests {
    @Test("Known identifiers get their name, unknown ones stay as they are")
    func modelNames() {
        #expect(DeviceInfo.modelName(for: "iPhone15,4") == "iPhone 15")
        #expect(DeviceInfo.modelName(for: "iPhone14,6") == "iPhone SE (3rd generation)")
        #expect(DeviceInfo.modelName(for: "iPhone18,3") == "iPhone 17")
        #expect(DeviceInfo.modelName(for: "iPhone18,4") == "iPhone Air")
        #expect(DeviceInfo.modelName(for: "iPhone99,9") == "iPhone99,9")
        #expect(DeviceInfo.modelName(for: "") == "")
    }

    @Test("The header names app, build, time, device and system")
    func header() {
        let lines = DeviceInfo.reportHeader(at: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Pingscape \(DeviceInfo.appVersion) (\(DeviceInfo.appBuild)) · "))
        // ISO 8601 with a space: 2027-01-15 09:20:00+01:00, in the device's time zone.
        #expect(lines[0].range(of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}([+-]\d{2}:\d{2}|Z)$"#, options: .regularExpression) != nil)
        #expect(lines[1] == "\(DeviceInfo.modelName) · iOS \(DeviceInfo.systemVersion)")
    }

    @Test("Row records become report rows one to one")
    func records() {
        let sections = [
            SectionRecord(
                title: "Wi-Fi",
                rows: [
                    RowRecord(label: "Name (SSID)", value: "HomeNet", sensitive: true),
                    RowRecord(label: "Security", value: "WPA2/WPA3 Personal", sensitive: false, preformatted: true),
                ])
        ]
        let report = sections.reportSections
        #expect(report.count == 1)
        #expect(report[0].title == "Wi-Fi")
        #expect(report[0].rows.map(\.label) == ["Name (SSID)", "Security"])
        #expect(report[0].rows.map(\.isSensitive) == [true, false])
        #expect(report[0].rows.map(\.isPreformatted) == [false, true])
        let masked = ReportFormatter.text(header: [], sections: report, masked: true)
        #expect(!masked.contains("HomeNet"))
        #expect(masked.contains("WPA2/WPA3 Personal"))
    }

    func withHidden(_ hidden: Bool, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: PrivacyMask.hideByDefaultKey)
        defaults.set(hidden, forKey: PrivacyMask.hideByDefaultKey)
        body()
        defaults.set(saved, forKey: PrivacyMask.hideByDefaultKey)
    }

    @Test("The Shortcuts text holds the connection, Wi-Fi, VPN and cellular")
    func shortcutText() {
        withHidden(false) {
            let text = StatusText.make(DemoData.snapshot, at: Date(timeIntervalSince1970: 1_800_000_000))
            for expected in ["192.168.178.42", "HomeNet", "utun4", "Online"] {
                #expect(text.contains(expected), "missing \(expected)")
            }
            #expect(text.hasPrefix("Pingscape "))
        }
    }

    @Test("With “Hide values by default” the Shortcuts text hides every address and the network name")
    func shortcutTextHidden() {
        withHidden(true) {
            let text = StatusText.make(DemoData.snapshot)
            for secret in ["192.168.178.42", "192.168.178.1", "255.255.255.0", "HomeNet", "3C:A6:2F:1B:D3:22", "10.250.10.1", "2001:db8"] {
                #expect(!text.contains(secret), "shows \(secret)")
            }
            #expect(text.contains(PrivacyMask.placeholder))
            #expect(text.contains("utun4"), "Interface names are not identifying and stay")
        }
    }
}

@Suite("Break points for long values")
struct BreakableTests {
    @Test("An invisible break follows every separator, and only those")
    func breaks() {
        #expect(DataRow.breakable("3C:A6") == "3C:\u{200B}A6")
        #expect(DataRow.breakable("a.b_c") == "a.\u{200B}b_\u{200B}c")
        #expect(DataRow.breakable("HomeNet") == "HomeNet")
    }

    @Test("Without the breaks the value is unchanged", arguments: [
        "2001:db8:4a1c:9e00:18c7:59b8:cdc:db7c", "192.168.178.42", "TLS_AES_128_GCM_SHA256", "", "•••••••",
    ])
    func lossless(_ value: String) {
        #expect(DataRow.breakable(value).replacingOccurrences(of: "\u{200B}", with: "") == value)
    }
}
