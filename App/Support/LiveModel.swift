import Foundation
import NetKit
import Observation

/// One point of a chart.
struct LivePoint: Identifiable, Equatable {
    let id: Int
    let time: Date
    let value: Double
}

/// One interface the Live tab can show.
struct LiveInterface: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let title: String
}

/// The numbers of the Live tab: throughput of one interface, latency, and the
/// events. Runs only while the tab is visible and the app is in front. iOS
/// suspends the app in the background anyway. Everything lives in memory, at
/// most 10 minutes of it.
@MainActor
@Observable
final class LiveModel {
    /// 10 minutes at one sample per second.
    static let capacity = 600

    nonisolated static let internetTargetKey = "liveInternetTarget"
    nonisolated static let internetHostKey = "liveInternetHost"

    private(set) var receive: [LivePoint] = []
    private(set) var send: [LivePoint] = []
    private(set) var latencyPoints: [LivePoint] = []
    private(set) var latency = LatencyWindow()
    private(set) var isRunning = false
    /// The interface the user picked. `nil` follows the one that carries traffic.
    var picked: String?

    /// The opt-in ping to a host on the internet, next to the one to the router.
    var usesInternetTarget: Bool {
        didSet { UserDefaults.standard.set(usesInternetTarget, forKey: Self.internetTargetKey) }
    }
    var internetHost: String {
        didSet { UserDefaults.standard.set(internetHost, forKey: Self.internetHostKey) }
    }

    private var sampler = RateSampler()
    private var counter = 0
    private let isDemo: Bool

    init(isDemo: Bool = DemoLaunch.isDemo) {
        self.isDemo = isDemo
        usesInternetTarget = UserDefaults.standard.bool(forKey: Self.internetTargetKey)
        internetHost = UserDefaults.standard.string(forKey: Self.internetHostKey) ?? "1.1.1.1"
        if isDemo { loadDemo() }
    }

    // MARK: Which interface

    /// The interfaces worth watching: Wi-Fi, cable, tunnels and cellular.
    func interfaces(in snapshot: NetworkSnapshot) -> [LiveInterface] {
        var result: [LiveInterface] = []
        for interface in snapshot.interfaces where interface.isUp {
            switch interface.kind {
            case .wifi where interface.hasUsableAddress:
                result.append(LiveInterface(name: interface.name, title: String(localized: "Wi-Fi")))
            case .ethernet where interface.hasUsableAddress:
                result.append(LiveInterface(name: interface.name, title: String(localized: "Ethernet")))
            case .cellular where interface.hasUsableAddress:
                if !result.contains(where: { $0.title == String(localized: "Cellular") }) {
                    result.append(LiveInterface(name: interface.name, title: String(localized: "Cellular")))
                }
            default:
                if snapshot.isVPN(interface) {
                    result.append(LiveInterface(name: interface.name, title: "VPN \(interface.name)"))
                }
            }
        }
        return result
    }

    /// The interface shown: the user's pick, else the one that carries the
    /// internet traffic, else the first.
    func selected(in snapshot: NetworkSnapshot) -> LiveInterface? {
        let all = interfaces(in: snapshot)
        if let picked, let match = all.first(where: { $0.name == picked }) { return match }
        if let carrying = snapshot.defaultRoutes.first(where: { $0.isActive })?.interfaceName,
            let match = all.first(where: { $0.name == carrying })
        {
            return match
        }
        return all.first
    }

    /// Who is pinged for latency: the router of a Wi-Fi or cable connection.
    /// Cellular has no useful local target.
    func gatewayTarget(in snapshot: NetworkSnapshot, interface: LiveInterface?) -> String? {
        guard let interface, let network = snapshot.interfaces.first(where: { $0.name == interface.name }),
            network.kind == .wifi || network.kind == .ethernet
        else { return nil }
        return snapshot.gateway(of: network)
    }

    // MARK: Sampling

    /// Reads the counters once a second until cancelled.
    func sample(interface name: String) async {
        guard !isDemo else { return }
        isRunning = true
        defer { isRunning = false }
        sampler.reset()
        while !Task.isCancelled {
            let interfaces = await Task.detached(priority: .utility) { InterfaceCollector.collect() }.value
            if let interface = interfaces.first(where: { $0.name == name }),
                let received = interface.receivedBytes, let sent = interface.sentBytes
            {
                let now = Date()
                if let sample = sampler.sample(received: received, sent: sent, at: now) {
                    append(&receive, sample.receivedBytesPerSecond, at: now)
                    append(&send, sample.sentBytesPerSecond, at: now)
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Clears the throughput charts, for another interface.
    func resetThroughput() {
        guard !isDemo else { return }
        receive = []
        send = []
        sampler.reset()
    }

    /// Pings a target once a second until cancelled.
    func ping(_ target: String) async {
        guard !isDemo else { return }
        var resolved = ResolvedAddress(literal: target)
        if resolved == nil { resolved = (try? await HostResolver.resolve(target))?.first }
        guard let address = resolved else { return }
        for await event in PingTool.run(address: address) {
            let now = Date()
            switch event {
            case .reply(_, _, let milliseconds, _):
                latency.record(milliseconds: milliseconds)
                append(&latencyPoints, milliseconds, at: now)
            case .noReply, .failed:
                latency.record(milliseconds: nil)
            case .started:
                break
            }
        }
    }

    func resetLatency() {
        guard !isDemo else { return }
        latency = LatencyWindow()
        latencyPoints = []
    }

    private func append(_ points: inout [LivePoint], _ value: Double, at time: Date) {
        counter += 1
        points.append(LivePoint(id: counter, time: time, value: value))
        if points.count > Self.capacity { points.removeFirst(points.count - Self.capacity) }
    }

    // MARK: Demo

    private func loadDemo() {
        let now = Date()
        for index in 0..<120 {
            let time = now.addingTimeInterval(Double(index - 120))
            let wave = (sin(Double(index) / 9) + 1) / 2
            receive.append(LivePoint(id: index, time: time, value: 300_000 + wave * 1_500_000 + Double(index % 7) * 40_000))
            send.append(LivePoint(id: index, time: time, value: 40_000 + wave * 120_000))
            let ms = 3 + wave * 2
            latencyPoints.append(LivePoint(id: index, time: time, value: ms))
            latency.record(milliseconds: ms)
        }
        counter = 120
        isRunning = true
    }
}
