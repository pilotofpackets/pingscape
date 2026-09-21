import CryptoKit
import Foundation

/// The raw collector data of one moment as JSON, for a bug report about a
/// wrong VPN or connection reading. A maintainer turns it into a test fixture.
///
/// It holds the snapshot the collectors made, not the prepared display. The
/// `derived` block helps reading but is not the truth: a test always computes
/// it again from the raw data. Fields are only ever added (`schemaVersion`), so
/// an old dump stays readable. External values (public IP, provider), LAN
/// devices and tool results are not part of it.
public struct DiagnosticDump: Sendable, Codable {
    public static let currentSchemaVersion = 1

    public struct App: Sendable, Codable, Equatable {
        public var version: String
        public var build: String
        public init(version: String, build: String) {
            self.version = version
            self.build = build
        }
    }

    public struct Device: Sendable, Codable, Equatable {
        /// The model identifier, such as `iPhone17,3`.
        public var model: String
        public var os: String
        public init(model: String, os: String) {
            self.model = model
            self.os = os
        }
    }

    public struct Derived: Sendable, Codable, Equatable {
        public var isVPN: Bool
        public var primaryInterface: String?
        public var tunnelScope: String?
        public var carriesTrafficThroughTunnel: Bool
        public var vpnInterfaces: [String]
    }

    public var schemaVersion: Int
    public var app: App
    public var device: Device
    public var takenAt: Date
    public var anonymized: Bool
    public var snapshot: NetworkSnapshot
    public var derived: Derived

    /// `anonymize` replaces addresses and names, see `SnapshotAnonymizer`.
    public init(
        snapshot: NetworkSnapshot, app: App, device: Device, anonymize: Bool, takenAt: Date = Date(),
        key: SymmetricKey = SymmetricKey(size: .bits256)
    ) {
        var cleaned = snapshot
        cleaned.publicIPv4 = .none
        cleaned.publicIPv6 = .none
        if anonymize {
            var anonymizer = SnapshotAnonymizer(key: key)
            cleaned = anonymizer.anonymize(cleaned)
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.app = app
        self.device = device
        self.takenAt = takenAt
        self.anonymized = anonymize
        self.snapshot = cleaned
        self.derived = Derived(
            isVPN: cleaned.isVPNActive,
            primaryInterface: cleaned.primaryInterface?.name,
            tunnelScope: cleaned.tunnelScope.map { $0 == .full ? "full" : "split" },
            carriesTrafficThroughTunnel: cleaned.vpnInterfaces.contains { cleaned.carriesTraffic($0) },
            vpnInterfaces: cleaned.vpnInterfaces.map(\.name))
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> DiagnosticDump {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DiagnosticDump.self, from: data)
    }
}
