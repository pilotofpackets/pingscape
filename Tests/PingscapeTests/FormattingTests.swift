import Foundation
import Testing

@testable import Pingscape

/// The numbers in the user's own format: "1.00" in English, "1,00" in German.
/// The tests check thresholds, digits and units, in whatever region the simulator has.
private func number(_ value: Double, digits: Int) -> String {
    value.formatted(.number.precision(.fractionLength(digits)))
}

@Suite("Units and numbers")
struct FormattingTests {
    @Test("Below one megabit the rate is in kbit/s, without decimals")
    func kilobits() {
        #expect(RateUnit.megabitPerSecond.string(bytesPerSecond: 0) == "\(number(0, digits: 0)) kbit/s")
        #expect(RateUnit.megabitPerSecond.string(bytesPerSecond: 100_000) == "\(number(800, digits: 0)) kbit/s")
        // Just under a megabit rounds to 1000 kbit/s rather than switching unit.
        #expect(RateUnit.megabitPerSecond.string(bytesPerSecond: 124_999) == "\(number(1_000, digits: 0)) kbit/s")
    }

    @Test("From one megabit: two decimals below 10, one above")
    func megabits() {
        #expect(RateUnit.megabitPerSecond.string(bytesPerSecond: 125_000) == "\(number(1, digits: 2)) Mbit/s")
        #expect(RateUnit.megabitPerSecond.string(bytesPerSecond: 1_234_567) == "\(number(9.876536, digits: 2)) Mbit/s")
        #expect(RateUnit.megabitPerSecond.string(bytesPerSecond: 1_250_000) == "\(number(10, digits: 1)) Mbit/s")
        #expect(RateUnit.megabitPerSecond.string(bytesPerSecond: 125_000_000) == "\(number(1_000, digits: 1)) Mbit/s")
    }

    @Test("Bytes per second count bytes, not bits")
    func megabytes() {
        #expect(RateUnit.megabytePerSecond.string(bytesPerSecond: 999_999) == "\(number(1_000, digits: 0)) kB/s")
        #expect(RateUnit.megabytePerSecond.string(bytesPerSecond: 1_000_000) == "\(number(1, digits: 2)) MB/s")
        #expect(RateUnit.megabytePerSecond.string(bytesPerSecond: 12_345_678) == "\(number(12.345678, digits: 1)) MB/s")
    }

    @Test("Every unit has a stable raw value for UserDefaults")
    func rawValues() {
        #expect(RateUnit.allCases.map(\.rawValue) == ["megabitPerSecond", "megabytePerSecond"])
        #expect(RateUnit(rawValue: "nonsense") == nil)
    }

    @Test("Milliseconds: one decimal below 10, whole numbers from 10")
    func millisecondsText() {
        #expect(milliseconds(0) == "\(number(0, digits: 1)) ms")
        #expect(milliseconds(0.44) == "\(number(0.4, digits: 1)) ms")
        #expect(milliseconds(9.94) == "\(number(9.9, digits: 1)) ms")
        #expect(milliseconds(10) == "10 ms")
        #expect(milliseconds(12.5) == "13 ms")
        #expect(milliseconds(1_234.4) == "1234 ms")
    }

    @Test("Byte sizes have no thousands separator, like ifconfig")
    func bytesText() {
        #expect(byteCount(1) == "1 byte")
        #expect(byteCount(1420) == "1420 bytes")
        #expect(byteCount(65_535) == "65535 bytes")
    }

    @Test("Counters are grouped the way the region does it")
    func byteCounts() {
        #expect(ByteCount.number(812_340) == Int64(812_340).formatted(.number))
        #expect(ByteCount.number(UInt64.max) == Int64.max.formatted(.number), "Too large a counter is clamped, not wrapped")
        #expect(ByteCount.string(88_000_000) == ByteCountFormatter.string(fromByteCount: 88_000_000, countStyle: .file))
        #expect(ByteCount.string(UInt64.max) == ByteCountFormatter.string(fromByteCount: .max, countStyle: .file))
    }
}

@Suite("Wrapping long values")
struct WrappingTests {
    @Test("An IPv6 address breaks at a colon, never inside a group")
    func ipv6() {
        let wrapped = DataRow.wrapped("2001:db8:4a1c:9e00:18c7:59b8:cdc:db7c")
        #expect(wrapped == "2001:db8:4a1c:9e00:\n18c7:59b8:cdc:db7c")
    }

    @Test("An IPv4 address breaks at a dot")
    func ipv4() {
        #expect(DataRow.wrapped("192.168.178.42") == "192.168.\n178.42")
    }

    @Test("A cipher suite breaks at an underscore, without a hyphen")
    func cipher() {
        let wrapped = DataRow.wrapped("TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256")
        #expect(!wrapped.contains("-"))
        #expect(wrapped.replacingOccurrences(of: "\n", with: "") == "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256")
        #expect(wrapped.split(separator: "\n").count == 2)
    }

    @Test("Text without a separator stays whole")
    func noSeparator() {
        #expect(DataRow.wrapped("HomeNet") == "HomeNet")
        #expect(DataRow.wrapped("") == "")
    }

    @Test("Each line of a list is split on its own, a short one stays whole")
    func list() {
        let wrapped = DataRow.wrapped("2001:4860:4860::8888\n8.8.8.8")
        let lines = wrapped.split(separator: "\n").map(String.init)
        #expect(lines.contains("8.8.8.8"))
        #expect(lines.allSatisfy { $0.count > 1 }, "No lone character on a line: \(lines)")
        #expect(wrapped.replacingOccurrences(of: "\n", with: "") == "2001:4860:4860::88888.8.8.8")
    }

    @Test("Nothing is lost or added by wrapping", arguments: [
        "fe80::1c3a:52ff:fe91:7d40", "3C:A6:2F:1B:D3:22", "a.b", "...", "one.one.one.one", "x_y_z",
    ])
    func lossless(_ value: String) {
        #expect(DataRow.wrapped(value).replacingOccurrences(of: "\n", with: "") == value)
    }
}
