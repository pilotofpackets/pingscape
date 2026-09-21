import Foundation

/// One Bonjour service a device announces.
public struct LANService: Sendable, Hashable {
    /// `_airplay._tcp`
    public let type: String
    /// The instance name the device gave the service.
    public let name: String
    public let port: Int?
    /// TXT record entries, as the device delivers them.
    public let txt: [String: String]

    public init(type: String, name: String, port: Int? = nil, txt: [String: String] = [:]) {
        self.type = type
        self.name = name
        self.port = port
        self.txt = txt
    }

    /// The MAC address the service announces, where the protocol defines one:
    /// AirPlay's `deviceid`, the address in the name of `_workstation._tcp`
    /// ("host [aa:bb:cc:dd:ee:ff]") and the prefix of an AirPlay audio name
    /// ("AABBCCDDEEFF@Name"). Other services carry identifiers that only look
    /// like a MAC address (HomeKit's `id` is random), so they are not read.
    public var announcedMAC: String? {
        switch type {
        case "_airplay._tcp":
            return txt["deviceid"].flatMap(MACAddress.canonical)
        case "_workstation._tcp":
            guard let open = name.lastIndex(of: "["), let close = name.lastIndex(of: "]"), open < close
            else { return nil }
            return MACAddress.canonical(String(name[name.index(after: open)..<close]))
        case "_raop._tcp":
            guard let at = name.firstIndex(of: "@"), name.distance(from: name.startIndex, to: at) == 12 else {
                return nil
            }
            return MACAddress.canonical(String(name[..<at]))
        default:
            return nil
        }
    }

    /// The name without a MAC prefix or suffix, for showing.
    public var displayName: String {
        switch type {
        case "_raop._tcp":
            if let at = name.firstIndex(of: "@"), announcedMAC != nil { return String(name[name.index(after: at)...]) }
        case "_workstation._tcp":
            if let open = name.lastIndex(of: "["), announcedMAC != nil {
                return name[..<open].trimmingCharacters(in: .whitespaces)
            }
        default:
            break
        }
        return name
    }
}

/// A device found on the local network.
public struct LANDevice: Sendable, Equatable, Identifiable {
    public var id: String { ip }

    public let ip: String
    /// The ping round trip. `nil` if the device did not answer a ping.
    public var latencyMilliseconds: Double?
    public var answeredPing: Bool
    /// The name from a reverse DNS lookup.
    public var hostname: String?
    public var services: [LANService]
    /// A MAC address a service announced.
    public var macAddress: String?
    /// Ports that accepted a connection in the thorough search.
    public var openPorts: [Int]

    public init(
        ip: String, latencyMilliseconds: Double? = nil, answeredPing: Bool = false, hostname: String? = nil,
        services: [LANService] = [], macAddress: String? = nil, openPorts: [Int] = []
    ) {
        self.ip = ip
        self.latencyMilliseconds = latencyMilliseconds
        self.answeredPing = answeredPing
        self.hostname = hostname
        self.services = services
        self.macAddress = macAddress
        self.openPorts = openPorts
    }

    /// Services in the order of how well their name describes the device.
    private static let namePriority = [
        "_airplay._tcp", "_googlecast._tcp", "_hap._tcp", "_companion-link._tcp", "_raop._tcp", "_sonos._tcp",
        "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_smb._tcp", "_afpovertcp._tcp", "_ssh._tcp", "_sftp-ssh._tcp",
        "_workstation._tcp", "_http._tcp", "_https._tcp",
    ]

    /// The name the device gave itself over Bonjour. Google Cast delivers the
    /// user's name for the device in `fn`.
    public var bonjourName: String? {
        let ranked = services.sorted { lhs, rhs in
            (Self.namePriority.firstIndex(of: lhs.type) ?? .max) < (Self.namePriority.firstIndex(of: rhs.type) ?? .max)
        }
        for service in ranked {
            if service.type == "_googlecast._tcp", let name = service.txt["fn"], !name.isEmpty { return name }
            let name = service.displayName
            if !name.isEmpty { return name }
        }
        return nil
    }

    /// The name to show: what the device announces, else its reverse DNS name.
    public var displayName: String? { bonjourName ?? hostname }
}

/// What the search reports while it runs.
public enum LANEvent: Sendable, Equatable {
    case started(network: String, total: Int, capped: Bool)
    case progress(done: Int, total: Int)
    case ping(ip: String, milliseconds: Double)
    /// A device that answered the thorough TCP probes but not the ping.
    case reachable(ip: String)
    case hostname(ip: String, name: String)
    case service(ip: String, LANService)
    case ports(ip: String, [Int])
    case failed(ToolError)
    case finished
}

/// The devices found so far. It applies events and keeps the list stable:
/// a device never moves because a name or a service arrived later.
public struct LANDeviceList: Sendable, Equatable {
    public private(set) var devices: [LANDevice] = []

    public init() {}

    private mutating func update(_ ip: String, _ change: (inout LANDevice) -> Void) {
        if let index = devices.firstIndex(where: { $0.ip == ip }) {
            change(&devices[index])
        } else {
            var device = LANDevice(ip: ip)
            change(&device)
            devices.append(device)
        }
    }

    public mutating func apply(_ event: LANEvent) {
        switch event {
        case .ping(let ip, let milliseconds):
            update(ip) {
                $0.answeredPing = true
                $0.latencyMilliseconds = milliseconds
            }
        case .reachable(let ip):
            update(ip) { _ in }
        case .hostname(let ip, let name):
            update(ip) { $0.hostname = name }
        case .service(let ip, let service):
            update(ip) {
                if !$0.services.contains(service) { $0.services.append(service) }
                if $0.macAddress == nil { $0.macAddress = service.announcedMAC }
            }
        case .ports(let ip, let ports):
            update(ip) { $0.openPorts = ports.sorted() }
        case .started, .progress, .failed, .finished:
            break
        }
    }

    /// This device first, then the gateway, then the rest by address. Names and
    /// services do not change the order.
    public func sorted(thisDevice: String?, gateway: String?) -> [LANDevice] {
        func rank(_ device: LANDevice) -> Int {
            if device.ip == thisDevice { return 0 }
            if device.ip == gateway { return 1 }
            return 2
        }
        return devices.sorted { lhs, rhs in
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            return (IPv4.toInt(lhs.ip) ?? 0) < (IPv4.toInt(rhs.ip) ?? 0)
        }
    }
}
