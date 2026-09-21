import Darwin
import Foundation

public struct RDAPEvent: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case registration, lastChanged, expiration
    }

    public let action: Action
    /// The date as the registry wrote it (ISO 8601).
    public let date: String

    public init(action: Action, date: String) {
        self.action = action
        self.date = date
    }
}

/// The fields of an RDAP answer that the app shows. A field the answer does
/// not have stays empty and its row is left out.
public struct RDAPResult: Sendable, Equatable {
    /// The RDAP server that answered.
    public let server: String
    public let name: String?
    public let handle: String?
    public let status: [String]
    public let registrar: String?
    public let events: [RDAPEvent]
    public let nameservers: [String]
    /// The address range of an IP network, or the numbers of an AS.
    public let range: String?

    public init(
        server: String, name: String?, handle: String?, status: [String], registrar: String?,
        events: [RDAPEvent], nameservers: [String], range: String?
    ) {
        self.server = server
        self.name = name
        self.handle = handle
        self.status = status
        self.registrar = registrar
        self.events = events
        self.nameservers = nameservers
        self.range = range
    }
}

/// RDAP (RFC 9082/9083): the JSON successor of Whois. The responsible server
/// comes from the IANA bootstrap files, without an intermediary service that
/// could add its own errors.
public enum RDAPClient {
    static let bootstrapBase = "https://data.iana.org/rdap/"
    public static let timeoutSeconds = 12.0

    // MARK: Bootstrap

    /// Which RDAP server is responsible for what (RFC 9224).
    struct Bootstrap: Sendable, Equatable {
        struct Service: Sendable, Equatable {
            let keys: [String]
            let urls: [String]
        }

        let services: [Service]

        init(json: Data) throws {
            struct File: Decodable { let services: [[[String]]] }
            let file = try JSONDecoder().decode(File.self, from: json)
            services = file.services.compactMap { entry in
                entry.count == 2 ? Service(keys: entry[0], urls: entry[1]) : nil
            }
        }

        /// The HTTPS URL of a service, ending in `/`.
        private func base(of service: Service) -> String? {
            let url = service.urls.first { $0.hasPrefix("https://") } ?? service.urls.first
            guard var url else { return nil }
            if !url.hasSuffix("/") { url += "/" }
            return url
        }

        /// The service of a top-level domain: the last label of the name.
        func url(forDomain name: String) -> String? {
            guard let tld = name.lowercased().split(separator: ".").last.map(String.init) else { return nil }
            return services.first { $0.keys.contains(tld) }.flatMap(base)
        }

        /// The service with the most specific network that holds the address.
        func url(forIP address: String) -> String? {
            guard let target = ResolvedAddress(literal: address) else { return nil }
            var best: (length: Int, service: Service)?
            for service in services {
                for key in service.keys {
                    guard let (network, length) = Self.parseCIDR(key), network.isIPv6 == target.isIPv6,
                        Self.matches(target, network: network, length: length),
                        length >= (best?.length ?? -1)
                    else { continue }
                    best = (length, service)
                }
            }
            return best.flatMap { base(of: $0.service) }
        }

        func url(forASN number: UInt32) -> String? {
            for service in services {
                for key in service.keys {
                    let bounds = key.split(separator: "-").compactMap { UInt32($0) }
                    if bounds.count == 1, bounds[0] == number { return base(of: service) }
                    if bounds.count == 2, (bounds[0]...bounds[1]).contains(number) { return base(of: service) }
                }
            }
            return nil
        }

        private static func parseCIDR(_ text: String) -> (ResolvedAddress, Int)? {
            let parts = text.split(separator: "/")
            guard parts.count == 2, let length = Int(parts[1]), let address = ResolvedAddress(literal: String(parts[0]))
            else { return nil }
            return (address, length)
        }

        private static func matches(_ address: ResolvedAddress, network: ResolvedAddress, length: Int) -> Bool {
            // The address bytes start after the family and port fields.
            let offset = address.isIPv6 ? 8 : 4
            let size = address.isIPv6 ? 16 : 4
            var remaining = length
            for index in 0..<size where remaining > 0 {
                let bits = min(remaining, 8)
                let mask = UInt8(truncatingIfNeeded: 0xFF00 >> bits)
                if address.storage[offset + index] & mask != network.storage[offset + index] & mask { return false }
                remaining -= bits
            }
            return true
        }
    }

    // MARK: Lookup

    public static func lookup(_ target: LookupTarget) async throws -> RDAPResult {
        let (file, path): (String, String) =
            switch target {
            case .domain(let name): ("dns.json", "domain/\(name)")
            case .ip(let address): (ResolvedAddress(literal: address)?.isIPv6 == true ? "ipv6.json" : "ipv4.json", "ip/\(address)")
            case .asn(let number): ("asn.json", "autnum/\(number)")
            }
        let bootstrap = try Bootstrap(json: try await fetch(bootstrapBase + file))
        let base: String? =
            switch target {
            case .domain(let name): bootstrap.url(forDomain: name)
            case .ip(let address): bootstrap.url(forIP: address)
            case .asn(let number): bootstrap.url(forASN: number)
            }
        guard let base, let url = URL(string: base + path) else { throw ToolError.noRegistry }
        return try parse(try await fetch(url.absoluteString, accept: "application/rdap+json"), server: url.host ?? base)
    }

    private static func fetch(_ address: String, accept: String = "application/json") async throws -> Data {
        guard let url = URL(string: address) else { throw InputError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeoutSeconds)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw status == 404 ? ToolError.noRegistry : ToolError.failed("HTTP \(status)")
        }
        return data
    }

    // MARK: Reading an answer

    static func parse(_ data: Data, server: String) throws -> RDAPResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.unreadable
        }
        let registrar = (object["entities"] as? [[String: Any]])?
            .first { ($0["roles"] as? [String])?.contains("registrar") == true }
            .flatMap(formattedName)

        let events: [RDAPEvent] = (object["events"] as? [[String: Any]] ?? []).compactMap { event in
            guard let date = event["eventDate"] as? String, let action = event["eventAction"] as? String
            else { return nil }
            switch action {
            case "registration": return RDAPEvent(action: .registration, date: date)
            case "last changed": return RDAPEvent(action: .lastChanged, date: date)
            case "expiration": return RDAPEvent(action: .expiration, date: date)
            default: return nil
            }
        }

        var range: String?
        if let start = object["startAddress"] as? String, let end = object["endAddress"] as? String {
            range = "\(start) – \(end)"
        } else if let start = object["startAutnum"] as? Int, let end = object["endAutnum"] as? Int {
            range = start == end ? "AS\(start)" : "AS\(start) – AS\(end)"
        }

        return RDAPResult(
            server: server,
            name: (object["ldhName"] as? String) ?? (object["name"] as? String),
            handle: object["handle"] as? String,
            status: object["status"] as? [String] ?? [],
            registrar: registrar,
            events: events,
            nameservers: (object["nameservers"] as? [[String: Any]] ?? []).compactMap { $0["ldhName"] as? String },
            range: range)
    }

    /// The `fn` (formatted name) of an entity's vCard.
    private static func formattedName(of entity: [String: Any]) -> String? {
        guard let card = entity["vcardArray"] as? [Any], card.count == 2,
            let properties = card[1] as? [[Any]]
        else { return nil }
        for property in properties where (property.first as? String) == "fn" {
            if let value = property.last as? String, !value.isEmpty { return value }
        }
        return nil
    }
}
