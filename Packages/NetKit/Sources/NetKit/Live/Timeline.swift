import Foundation

/// How the device is connected, as far as the system says.
public enum ConnectionKind: String, Sendable, Codable, Equatable {
    case wifi, cellular, ethernet, other, offline
}

/// One change between two snapshots.
public enum TimelineChange: Sendable, Equatable {
    /// The connection the traffic goes through changed.
    case connection(from: ConnectionKind, to: ConnectionKind)
    case vpn(isActive: Bool)
    /// The Wi-Fi access point changed (roaming) within the same network.
    case bssid(from: String, to: String)
    case radio(from: RadioTechnology, to: RadioTechnology, isDataService: Bool)
}

public struct TimelineEntry: Sendable, Equatable, Identifiable {
    public let id: Int
    public let time: Date
    public let change: TimelineChange

    public init(id: Int, time: Date, change: TimelineChange) {
        self.id = id
        self.time = time
        self.change = change
    }
}

extension NetworkSnapshot {
    /// Online if the system says so, otherwise if a local interface has an address.
    public var isOnline: Bool { path?.isOnline ?? (primaryInterface != nil) }

    public var connectionKind: ConnectionKind {
        guard isOnline else { return .offline }
        switch primaryInterface?.kind {
        case .wifi: return .wifi
        case .cellular: return .cellular
        case .ethernet: return .ethernet
        default: return .other
        }
    }

    /// What changed from `old` to `self`.
    public func changes(since old: NetworkSnapshot) -> [TimelineChange] {
        var changes: [TimelineChange] = []
        if old.connectionKind != connectionKind {
            changes.append(.connection(from: old.connectionKind, to: connectionKind))
        }
        if old.isVPNActive != isVPNActive { changes.append(.vpn(isActive: isVPNActive)) }
        if case .value(let before) = old.wifi, case .value(let after) = wifi, before.ssid == after.ssid,
            let from = before.bssid.flatMap(MACAddress.canonical), let to = after.bssid.flatMap(MACAddress.canonical),
            from != to
        {
            changes.append(.bssid(from: from, to: to))
        }
        for service in cellularServices {
            guard let earlier = old.cellularServices.first(where: { $0.id == service.id }),
                earlier.technology != service.technology
            else { continue }
            changes.append(.radio(from: earlier.technology, to: service.technology, isDataService: service.isDataService))
        }
        return changes
    }
}

/// Changes seen while the app runs, newest first. Only in memory: it is gone
/// when the app ends.
public struct TimelineLog: Sendable, Equatable {
    public static let capacity = 100

    public private(set) var entries: [TimelineEntry] = []
    private var counter = 0

    public init() {}

    /// Records what changed between two snapshots. The first snapshot has no
    /// predecessor and records nothing.
    public mutating func record(from old: NetworkSnapshot?, to new: NetworkSnapshot, at time: Date = Date()) {
        guard let old else { return }
        for change in new.changes(since: old) {
            counter += 1
            entries.insert(TimelineEntry(id: counter, time: time, change: change), at: 0)
        }
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
    }

    public var bssidChanges: [TimelineEntry] {
        entries.filter { if case .bssid = $0.change { true } else { false } }
    }
}
