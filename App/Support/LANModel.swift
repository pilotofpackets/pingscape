import Foundation
import NetKit
import Observation

/// The search of the local network: its state, the devices found and what the
/// router says about itself. One instance for the app, so the list stays when
/// the user leaves the tab.
@MainActor
@Observable
final class LANModel {
    enum Phase: Equatable {
        case idle
        /// Waiting for the answer to the Local Network question.
        case askingPermission
        case searching
        case finished
        /// Stopped by the user or because the app left the foreground. The list
        /// may be incomplete, and the screen says so.
        case interrupted
    }

    nonisolated static let modeKey = "lanScanMode"
    nonisolated static let accessKey = "localNetworkAccess"

    private(set) var phase: Phase = .idle
    private(set) var list = LANDeviceList()
    private(set) var progress: (done: Int, total: Int)?
    private(set) var network: String?
    private(set) var isCapped = false
    private(set) var failure: ToolError?
    private(set) var routerInfo: RouterInfo?
    /// The last known answer to the Local Network question. iOS has no call to
    /// read it, so it is what the last search found out.
    private(set) var access: LocalNetworkAccess?
    private(set) var finishedAt: Date?

    /// "Quick" or "Thorough". Remembered.
    var mode: LANScanMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    private var task: Task<Void, Never>?
    private let isDemo: Bool

    init(isDemo: Bool = DemoLaunch.isDemo) {
        self.isDemo = isDemo
        mode = LANScanMode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .quick
        access = LocalNetworkAccess(rawValue: UserDefaults.standard.string(forKey: Self.accessKey) ?? "")
    }

    var isBusy: Bool { phase == .askingPermission || phase == .searching }

    /// The list for the screen: this device first, then the router, then by address.
    func devices(thisDevice: String?, gateway: String?) -> [LANDevice] {
        var devices = list.sorted(thisDevice: thisDevice, gateway: gateway)
        if let thisDevice, !devices.contains(where: { $0.ip == thisDevice }) {
            devices.insert(LANDevice(ip: thisDevice), at: 0)
        }
        return devices
    }

    func start(_ snapshot: NetworkSnapshot) {
        guard !isBusy, let range = snapshot.lanRange, let me = snapshot.primaryIPv4?.ip else { return }
        let gateway = snapshot.localGateway4
        task?.cancel()
        list = LANDeviceList()
        progress = nil
        failure = nil
        isCapped = false
        routerInfo = nil
        finishedAt = nil
        let mode = mode
        task = Task { [weak self] in
            guard let self else { return }
            if isDemo {
                await runDemo(gateway: gateway)
                return
            }
            phase = .askingPermission
            let answer = await LocalNetworkPermission.check()
            guard !Task.isCancelled else { return }
            if answer != .unknown { remember(answer) }
            if answer == .denied {
                phase = .idle
                return
            }
            phase = .searching
            async let router: RouterInfo? = gateway == nil ? nil : UPnPClient.describe(gateway: gateway!)
            for await event in LANScanner.run(range: range, thisDevice: me, mode: mode) {
                apply(event)
            }
            if !Task.isCancelled { routerInfo = await router }
            if !Task.isCancelled {
                phase = .finished
                finishedAt = Date()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if isBusy { phase = .interrupted }
    }

    private func apply(_ event: LANEvent) {
        switch event {
        case .started(let network, let total, let capped):
            self.network = network
            isCapped = capped
            progress = (0, total)
        case .progress(let done, let total):
            progress = (done, total)
        case .failed(let error):
            failure = error
        case .finished:
            break
        default:
            list.apply(event)
        }
    }

    private func remember(_ answer: LocalNetworkAccess) {
        access = answer
        UserDefaults.standard.set(answer.rawValue, forKey: Self.accessKey)
    }

    /// Looks at the permission again after the user came back from Settings.
    /// Only when the answer is known already, because asking the first time is
    /// the job of the search.
    func recheckAccess() async {
        guard access != nil, !isBusy else { return }
        let answer = await LocalNetworkPermission.check(timeoutSeconds: 3)
        if answer != .unknown { remember(answer) }
    }

    /// The router's own description, when the Local Network permission is known
    /// to be granted (a request to the router would ask for it otherwise).
    func loadRouterInfo(gateway: String) async {
        guard routerInfo == nil, access == .allowed || isDemo else { return }
        if isDemo {
            routerInfo = DemoLAN.routerInfo
            return
        }
        routerInfo = await UPnPClient.describe(gateway: gateway)
    }

    private func runDemo(gateway: String?) async {
        phase = .searching
        network = "192.168.178.0/24"
        progress = (0, 253)
        for event in DemoLAN.events {
            list.apply(event)
        }
        progress = (253, 253)
        routerInfo = DemoLAN.routerInfo
        access = .allowed
        phase = .finished
        finishedAt = Date()
    }
}

/// Fixture devices for the demo mode.
enum DemoLAN {
    static let events: [LANEvent] = [
        .ping(ip: "192.168.178.1", milliseconds: 2),
        .hostname(ip: "192.168.178.1", name: "fritz.box"),
        .ping(ip: "192.168.178.40", milliseconds: 4),
        .service(ip: "192.168.178.40", LANService(type: "_airplay._tcp", name: "Living Room TV", port: 7000, txt: ["model": "AppleTV6,2", "deviceid": "3C:A6:2F:1B:00:1F"])),
        .service(ip: "192.168.178.40", LANService(type: "_raop._tcp", name: "3CA62F1B001F@Living Room TV", port: 7000)),
        .ping(ip: "192.168.178.52", milliseconds: 6),
        .service(ip: "192.168.178.52", LANService(type: "_ipp._tcp", name: "Office Printer", port: 631, txt: ["ty": "Example LaserJet"])),
        .ports(ip: "192.168.178.52", [80, 443]),
        .ping(ip: "192.168.178.60", milliseconds: 3),
        .service(ip: "192.168.178.60", LANService(type: "_smb._tcp", name: "nas", port: 445)),
        .service(ip: "192.168.178.60", LANService(type: "_ssh._tcp", name: "nas", port: 22)),
        .hostname(ip: "192.168.178.60", name: "nas.fritz.box"),
        .ping(ip: "192.168.178.23", milliseconds: 11),
    ]

    static let routerInfo = RouterInfo(
        manufacturer: "Example Networks", model: "ER-7000", firmware: "8.20", externalIP: "203.0.113.57",
        uptimeSeconds: 3 * 86_400 + 4 * 3_600)
}
