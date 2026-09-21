import Foundation

/// The provider behind a public IP address: the autonomous system that
/// announces its network.
public struct ProviderInfo: Sendable, Hashable {
    /// `AS64500`
    public let asNumber: String
    /// The registered holder of the AS. `nil` if the registry has none.
    public let organization: String?
    /// The network the address belongs to, such as `203.0.113.0/24`.
    public let network: String?

    public init(asNumber: String, organization: String?, network: String?) {
        self.asNumber = asNumber
        self.organization = organization
        self.network = network
    }
}

/// The RIPEstat Data API (RIPE NCC): AS number and holder for an IP address.
///
/// Only the public IP address goes out, as the `resource`. No account, no key.
/// Terms of use: https://www.ripe.net/about-us/legal/ripestat-service-terms-and-conditions/
public enum RIPEstat {
    static let base = "https://stat.ripe.net/data/"
    /// RIPE asks apps to name themselves.
    static let sourceApp = "pingscape"
    public static let timeoutSeconds = 6.0

    /// The provider of an address, or `nil` if the address is not announced
    /// (private or unrouted). At most two requests, one after the other.
    public static func provider(for ip: String) async throws -> ProviderInfo? {
        let network = try networkInfo(try await fetch("network-info", resource: ip))
        guard let asNumber = network.asns.first else { return nil }
        let holder = try? holder(try await fetch("as-overview", resource: "AS\(asNumber)"))
        return ProviderInfo(asNumber: "AS\(asNumber)", organization: holder ?? nil, network: network.prefix)
    }

    private static func fetch(_ call: String, resource: String) async throws -> Data {
        var components = URLComponents(string: base + call + "/data.json")!
        components.queryItems = [
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "sourceapp", value: sourceApp),
        ]
        guard let url = components.url else { throw InputError.invalidURL }
        let request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeoutSeconds)
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw ToolError.failed("HTTP \(status)")
        }
        return data
    }

    // MARK: Reading answers

    /// `data` of an answer whose `status` is `ok`.
    private static func payload(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["status"] as? String == "ok",
            let payload = object["data"] as? [String: Any]
        else { throw ToolError.failed("RIPEstat did not answer") }
        return payload
    }

    /// The AS numbers that announce the network (as text, without "AS") and the network.
    static func networkInfo(_ data: Data) throws -> (asns: [String], prefix: String?) {
        let payload = try payload(data)
        // The field holds strings, but a number is read too.
        let asns = (payload["asns"] as? [Any] ?? []).compactMap { value -> String? in
            if let text = value as? String { return text }
            if let number = value as? Int { return String(number) }
            return nil
        }
        // A private address comes back with an empty prefix.
        let prefix = payload["prefix"] as? String
        return (asns, prefix?.isEmpty == false ? prefix : nil)
    }

    /// The holder of an AS, `nil` when the field is missing or `null`.
    static func holder(_ data: Data) throws -> String? {
        let holder = try payload(data)["holder"] as? String
        return holder?.isEmpty == false ? holder : nil
    }
}
