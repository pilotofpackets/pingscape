import Darwin
import Foundation

/// One answer in a Whois chain: the server and its text, as delivered.
public struct WhoisStep: Sendable, Equatable, Identifiable {
    public var id: String { server }
    public let server: String
    public let text: String

    public init(server: String, text: String) {
        self.server = server
        self.text = text
    }
}

/// Whois over TCP port 43. The query goes to IANA first and follows the
/// referral to the responsible registry, and from a registry on to the
/// registrar. The result is the raw text of each step. Whois has no fixed
/// format, so no fields are pulled out of it: that would be guessing.
public enum WhoisClient {
    public static let timeoutMilliseconds = 12_000
    static let firstServer = "whois.iana.org"
    /// IANA, the registry and the registrar.
    static let maximumSteps = 3
    static let maximumBytes = 512 * 1024

    /// IANA answers for the top-level domain (or the address), names the
    /// registry, and the registry names the registrar of a domain. The
    /// registrar step is optional: if that server does not answer, the
    /// registry's record stands.
    public static func lookup(_ target: LookupTarget) async throws -> [WhoisStep] {
        let ianaQuery: String
        switch target {
        case .domain(let name): ianaQuery = name.split(separator: ".").last.map(String.init) ?? name
        default: ianaQuery = target.whoisQuery
        }
        var steps = [WhoisStep(server: firstServer, text: try await ask(server: firstServer, query: ianaQuery))]
        guard let registry = referral(in: steps[0].text, from: firstServer, keys: ianaKeys) else { return steps }

        let registryText = try await ask(server: registry, query: query(for: target, at: registry))
        steps.append(WhoisStep(server: registry, text: registryText))
        if let registrar = referral(in: registryText, from: registry, keys: registryKeys),
            !steps.contains(where: { $0.server == registrar }), steps.count < maximumSteps,
            let text = try? await ask(server: registrar, query: query(for: target, at: registrar))
        {
            steps.append(WhoisStep(server: registrar, text: text))
        }
        return steps
    }

    /// A few servers want more than the bare name.
    static func query(for target: LookupTarget, at server: String) -> String {
        let name = target.whoisQuery
        if server.contains("denic.de") { return "-T dn " + name }
        if server.contains("arin.net"), case .ip = target { return "n + " + name }
        return name
    }

    static let ianaKeys = ["refer", "whois"]
    static let registryKeys = ["registrar whois server", "whois server", "refer", "referralserver"]

    /// The server a Whois text refers to under one of `keys`, or `nil`.
    ///
    /// IANA answers with `refer:`. A thin registry such as Verisign names the
    /// registrar in `Registrar WHOIS Server:`. ARIN uses `ReferralServer:`.
    static func referral(in text: String, from server: String, keys: [String]) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard keys.contains(key) else { continue }
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            for scheme in ["rwhois://", "whois://", "https://", "http://"] where value.lowercased().hasPrefix(scheme) {
                value = String(value.dropFirst(scheme.count))
            }
            // Drop a port and a path. Only the default port is used.
            value = String(value.split(whereSeparator: { $0 == ":" || $0 == "/" }).first ?? "")
            let host = value.lowercased()
            guard !host.isEmpty, host != server, host.contains("."),
                (try? ToolInput.host(host)) == host
            else { continue }
            return host
        }
        return nil
    }

    private static func ask(server: String, query: String) async throws -> String {
        let addresses = try await HostResolver.resolve(server)
        guard let address = addresses.first else { throw ToolError.cannotResolve }
        return try await Blocking.run { cancel in
            let deadline = Deadline(afterMilliseconds: timeoutMilliseconds)
            let socket = try POSIXSocket(family: address.family, type: SOCK_STREAM)
            try socket.connect(to: address, port: 43, deadline: deadline, cancel: cancel)
            try socket.sendAll(Array((query + "\r\n").utf8), deadline: deadline, cancel: cancel)
            var data: [UInt8] = []
            while data.count < maximumBytes {
                let chunk = try socket.receive(limit: 16 * 1024, deadline: deadline, cancel: cancel)
                if chunk.isEmpty { break }
                data += chunk
            }
            // Old registries answer in Latin-1.
            return String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
        }
    }
}
