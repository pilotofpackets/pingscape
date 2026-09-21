import Foundation
import Testing

@testable import NetKit

@Suite("Rate sampler")
struct RateSamplerTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func computesBytesPerSecondBetweenReadings() throws {
        var sampler = RateSampler()
        #expect(sampler.sample(received: 1_000, sent: 100, at: start) == nil)
        let result = sampler.sample(received: 3_000, sent: 600, at: start.addingTimeInterval(2))
        let sample = try #require(result)
        #expect(sample.receivedBytesPerSecond == 1_000)
        #expect(sample.sentBytesPerSecond == 250)
    }

    @Test func dropsTheSampleWhenACounterGoesBackwards() throws {
        var sampler = RateSampler()
        _ = sampler.sample(received: 5_000_000_000, sent: 100, at: start)
        // The counter restarted: no spike, no negative rate.
        #expect(sampler.sample(received: 1_000, sent: 200, at: start.addingTimeInterval(1)) == nil)
        // The next reading is measured from the new base.
        let result = sampler.sample(received: 2_000, sent: 300, at: start.addingTimeInterval(2))
        let sample = try #require(result)
        #expect(sample.receivedBytesPerSecond == 1_000)
    }

    @Test func ignoresReadingsWithoutElapsedTime() {
        var sampler = RateSampler()
        _ = sampler.sample(received: 1, sent: 1, at: start)
        #expect(sampler.sample(received: 2, sent: 2, at: start) == nil)
    }

    @Test func countersBeyond4GiBDoNotWrap() throws {
        var sampler = RateSampler()
        _ = sampler.sample(received: 4_294_967_000, sent: 0, at: start)
        let result = sampler.sample(received: 4_294_968_000, sent: 0, at: start.addingTimeInterval(1))
        let sample = try #require(result)
        #expect(sample.receivedBytesPerSecond == 1_000)
    }
}

@Suite("Latency window")
struct LatencyWindowTests {
    @Test func computesLossAndJitterOverTheWindow() {
        var window = LatencyWindow(size: 5)
        for value in [10.0, 14.0, nil, 12.0] { window.record(milliseconds: value) }
        #expect(window.count == 4)
        #expect(window.lostPercent == 25)
        #expect(window.jitter == 3)
        #expect(window.latest == 12)
    }

    @Test func dropsTheOldestResults() {
        var window = LatencyWindow(size: 3)
        for value in [nil, 10.0, 10.0, 10.0] { window.record(milliseconds: value) }
        #expect(window.count == 3)
        #expect(window.lostPercent == 0)
    }

    @Test func hasNoValuesBeforeTheFirstPing() {
        let window = LatencyWindow()
        #expect(window.lostPercent == nil && window.jitter == nil && window.latest == nil)
    }

    @Test func latestIsNilAfterALostPing() {
        var window = LatencyWindow()
        window.record(milliseconds: 5)
        window.record(milliseconds: nil)
        #expect(window.latest == nil)
    }
}

@Suite("Timeline")
struct TimelineTests {
    private func wifiSnapshot(bssid: String = "3C:A6:2F:1B:00:1F", ssid: String = "HomeNet") -> NetworkSnapshot {
        NetworkSnapshot(
            path: PathSummary(isOnline: true),
            interfaces: [
                NetworkInterface(name: "en0", addresses: [InterfaceAddress(ip: "192.168.178.42", isIPv6: false, prefixLength: 24)])
            ],
            wifi: .value(WiFiInfo(ssid: ssid, bssid: bssid)))
    }

    private var cellularSnapshot: NetworkSnapshot {
        NetworkSnapshot(
            path: PathSummary(isOnline: true),
            interfaces: [
                NetworkInterface(name: "pdp_ip0", addresses: [InterfaceAddress(ip: "100.72.31.14", isIPv6: false, prefixLength: 30)])
            ],
            cellularServices: [CellularService(id: "a", isDataService: true, technology: .lte)])
    }

    @Test func recordsNothingForTheFirstSnapshot() {
        var log = TimelineLog()
        log.record(from: nil, to: wifiSnapshot())
        #expect(log.entries.isEmpty)
    }

    @Test func recordsAChangeOfConnection() {
        var log = TimelineLog()
        log.record(from: wifiSnapshot(), to: cellularSnapshot)
        #expect(log.entries.map(\.change) == [.connection(from: .wifi, to: .cellular)])
    }

    @Test func recordsGoingOffline() {
        var offline = NetworkSnapshot(path: PathSummary(isOnline: false))
        offline.interfaces = []
        var log = TimelineLog()
        log.record(from: wifiSnapshot(), to: offline)
        #expect(log.entries.first?.change == .connection(from: .wifi, to: .offline))
    }

    @Test func recordsRoamingBetweenAccessPoints() {
        var log = TimelineLog()
        log.record(from: wifiSnapshot(), to: wifiSnapshot(bssid: "3C:A6:2F:1B:00:20"))
        #expect(log.entries.map(\.change) == [.bssid(from: "3C:A6:2F:1B:00:1F", to: "3C:A6:2F:1B:00:20")])
        #expect(log.bssidChanges.count == 1)
    }

    @Test func readsBSSIDsThatDropLeadingZeros() {
        var log = TimelineLog()
        log.record(from: wifiSnapshot(bssid: "0:1a:2b:3c:4d:5e"), to: wifiSnapshot(bssid: "00:1A:2B:3C:4D:5E"))
        #expect(log.entries.isEmpty)
    }

    @Test func aDifferentNetworkIsNoRoaming() {
        var log = TimelineLog()
        log.record(from: wifiSnapshot(), to: wifiSnapshot(bssid: "AA:BB:CC:00:00:01", ssid: "Cafe"))
        #expect(log.entries.isEmpty)
    }

    @Test func recordsTheVPNComingUp() {
        var withVPN = wifiSnapshot()
        withVPN.interfaces.append(NetworkInterface(name: "utun4", addresses: [InterfaceAddress(ip: "10.250.10.1", isIPv6: false, prefixLength: 32)]))
        withVPN.vpnServiceInterfaces = ["utun4"]
        var log = TimelineLog()
        log.record(from: wifiSnapshot(), to: withVPN)
        #expect(log.entries.map(\.change) == [.vpn(isActive: true)])
    }

    @Test func recordsARadioTechnologyChange() {
        var faster = cellularSnapshot
        faster.cellularServices = [CellularService(id: "a", isDataService: true, technology: .nrNonStandalone)]
        var log = TimelineLog()
        log.record(from: cellularSnapshot, to: faster)
        #expect(log.entries.map(\.change) == [.radio(from: .lte, to: .nrNonStandalone, isDataService: true)])
    }

    @Test func keepsNewestFirstAndTheLast100() {
        var log = TimelineLog()
        var toggle = false
        for _ in 0..<150 {
            let next = toggle ? wifiSnapshot() : cellularSnapshot
            log.record(from: toggle ? cellularSnapshot : wifiSnapshot(), to: next)
            toggle.toggle()
        }
        #expect(log.entries.count == TimelineLog.capacity)
        #expect(log.entries.first!.id > log.entries.last!.id)
    }

    @Test func staysQuietWithoutChanges() {
        var log = TimelineLog()
        log.record(from: wifiSnapshot(), to: wifiSnapshot())
        #expect(log.entries.isEmpty)
    }
}
