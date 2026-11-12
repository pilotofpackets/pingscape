import AppIntents
import Foundation
import NetKit

// The tools as Shortcuts actions. Each one measures once when it runs and
// returns what it measured; nothing runs in the background.

enum DNSQueryType: String, AppEnum, CaseIterable {
    case a, aaaa, cname, mx, ns, txt, soa, ptr, srv, caa

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Record type"
    static let caseDisplayRepresentations: [DNSQueryType: DisplayRepresentation] = [
        .a: "A", .aaaa: "AAAA", .cname: "CNAME", .mx: "MX", .ns: "NS", .txt: "TXT", .soa: "SOA", .ptr: "PTR",
        .srv: "SRV", .caa: "CAA",
    ]

    var recordType: DNSRecordType { DNSRecordType(rawValue: rawValue.uppercased()) ?? .a }
}

enum DNSServerOption: String, AppEnum, CaseIterable {
    case system, cloudflare, google, quad9

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "DNS server"
    static let caseDisplayRepresentations: [DNSServerOption: DisplayRepresentation] = [
        .system: "System (current network)", .cloudflare: "Cloudflare (1.1.1.1)", .google: "Google (8.8.8.8)",
        .quad9: "Quad9 (9.9.9.9)",
    ]

    func address(in snapshot: NetworkSnapshot) -> ResolvedAddress? {
        let text: String? =
            switch self {
            case .system: snapshot.dnsServers.first
            case .cloudflare: "1.1.1.1"
            case .google: "8.8.8.8"
            case .quad9: "9.9.9.9"
            }
        return text.flatMap(ResolvedAddress.init(literal:))
    }
}

struct DNSLookupIntent: AppIntent {
    static let title: LocalizedStringResource = "Look up DNS records"
    static let description = IntentDescription(
        "Asks a DNS server for the records of a name and returns their values, one item per record. For PTR, enter an IP address.")
    static let openAppWhenRun = false

    @Parameter(title: "Name", description: "A host name, or an IP address for PTR", requestValueDialog: "Which name?")
    var name: String

    @Parameter(title: "Type", default: .a)
    var type: DNSQueryType

    @Parameter(title: "Server", default: .system)
    var server: DNSServerOption

    static var parameterSummary: some ParameterSummary {
        Summary("Look up \(\.$type) records of \(\.$name)") { \.$server }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        guard let address = server.address(in: await IntentSupport.snapshot()) else {
            throw IntentMessage(String(localized: "No DNS servers right now"))
        }
        let response: DNSResponse
        do {
            let input = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if type == .ptr, ToolInput.isIPv4(input) || ToolInput.isIPv6(input) {
                response = try await DNSClient.reverse(ip: input, server: address)
            } else {
                response = try await DNSClient.query(name: input, type: type.recordType, server: address)
            }
        } catch {
            throw IntentMessage(error, target: address)
        }
        guard response.responseCode == 0 else {
            throw IntentMessage(String(localized: "The server answered \(response.responseCodeName)"))
        }
        // A CNAME chain comes along with an A query. The records asked for come
        // first; if there are none, the chain is the answer.
        let matching = response.answers.filter { $0.type == type.recordType.rawValue }
        let values = (matching.isEmpty ? response.answers : matching).map(\.value)
        let spoken = values.isEmpty ? String(localized: "No records") : values.joined(separator: ", ")
        return .result(value: values, dialog: IntentSupport.dialog("\(name) \(type.recordType.rawValue): \(spoken)"))
    }
}

struct CheckPortIntent: AppIntent {
    static let title: LocalizedStringResource = "Check a port"
    static let description = IntentDescription(
        "Tries a TCP connection to one port and tells whether it is open. Only the handshake happens, no data is sent.")
    static let openAppWhenRun = false

    @Parameter(title: "Host", description: "A host name or IP address", requestValueDialog: "Which host?")
    var host: String

    @Parameter(title: "Port", default: 443, inclusiveRange: (1, 65535), requestValueDialog: "Which port?")
    var port: Int

    static var parameterSummary: some ParameterSummary { Summary("Check port \(\.$port) on \(\.$host)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let target = try await IntentSupport.target(host)
        for await event in PortScanner.run(address: target.address, ports: [port]) {
            switch event {
            case .result(_, let state, let ms):
                let time = ms.map { " (\(milliseconds($0)))" } ?? ""
                switch state {
                case .open:
                    return .result(value: true, dialog: IntentSupport.dialog(String(localized: "Port \(port) on \(host) is open") + time))
                case .closed:
                    return .result(value: false, dialog: IntentSupport.dialog(String(localized: "Port \(port) on \(host) is closed") + time))
                case .noResponse:
                    return .result(value: false, dialog: IntentSupport.dialog(String(localized: "Port \(port) on \(host) did not answer")))
                }
            case .failed(let error):
                throw IntentMessage(error, target: target.address)
            case .started, .progress, .finished:
                continue
            }
        }
        throw IntentMessage(ToolError.timeout)
    }
}

struct CertificateExpiryIntent: AppIntent {
    static let title: LocalizedStringResource = "Days until a certificate expires"
    static let description = IntentDescription(
        "Connects with TLS and returns how many days the server's certificate is still valid. Negative if it has expired.")
    static let openAppWhenRun = false

    @Parameter(title: "Host", description: "A host name, optionally with :port", requestValueDialog: "Which host?")
    var host: String

    static var parameterSummary: some ParameterSummary { Summary("Days until the certificate of \(\.$host) expires") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let report: TLSReport
        do {
            let target = try ToolInput.hostAndPort(host, defaultPort: 443)
            report = try await TLSInspector.inspect(host: target.host, port: target.port ?? 443)
        } catch {
            throw IntentMessage(error)
        }
        guard let leaf = report.chain.first else { throw IntentMessage(ToolError.unreadable) }
        let days = leaf.daysUntilExpiry()
        let date = leaf.notAfter.formatted(date: .abbreviated, time: .omitted)
        var text =
            days >= 0
            ? String(localized: "Valid for \(days) more days, until \(date)")
            : String(localized: "Expired \(-days) days ago, on \(date)")
        if case .untrusted(let reason) = report.trust {
            text += ". " + String(localized: "Not trusted: \(reason)")
        }
        return .result(value: days, dialog: IntentSupport.dialog(text))
    }
}

struct HTTPCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "Check a website"
    static let description = IntentDescription(
        "Loads the headers of a web address, follows redirects and returns the final HTTP status code. Says how long it took.")
    static let openAppWhenRun = false

    @Parameter(title: "Address", description: "A web address such as https://example.com", requestValueDialog: "Which address?")
    var address: String

    static var parameterSummary: some ParameterSummary { Summary("Check \(\.$address)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let steps: [HTTPTimingStep]
        do {
            steps = try await HTTPTimer.measure(try HTTPTimer.url(from: address))
        } catch {
            throw IntentMessage(error)
        }
        guard let last = steps.last, let status = last.statusCode else { throw IntentMessage(ToolError.unreadable) }
        let total = steps.compactMap(\.totalMilliseconds).reduce(0, +)
        var text = "HTTP \(status) · \(milliseconds(total))"
        if steps.count > 1 { text += " · " + String(localized: "\(steps.count - 1) redirects") }
        return .result(value: status, dialog: IntentSupport.dialog(text))
    }
}

struct TracerouteIntent: AppIntent {
    static let title: LocalizedStringResource = "Trace the route to a host"
    static let description = IntentDescription(
        "Finds the routers on the way to a host, one probe per hop, and returns one line per hop. Hops that did not answer show as an asterisk.")
    static let openAppWhenRun = false

    @Parameter(title: "Host", description: "A host name or IP address", requestValueDialog: "Which host?")
    var host: String

    static var parameterSummary: some ParameterSummary { Summary("Trace the route to \(\.$host)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let target = try await IntentSupport.target(host)
        // One probe per hop and no reverse lookups keep it within the time
        // Siri waits for an answer.
        var settings = TracerouteSettings()
        settings.probesPerHop = 1
        settings.timeoutSeconds = 1
        settings.resolveNames = false
        var lines: [String] = []
        var reached = false
        for await event in TracerouteTool.run(address: target.address, settings: settings) {
            switch event {
            case .hop(let hop):
                let time = hop.times.compactMap { $0 }.first.map(milliseconds) ?? ""
                lines.append([String(hop.number), hop.address ?? "*", time].filter { !$0.isEmpty }.joined(separator: "  "))
            case .finished(let reachedTarget):
                reached = reachedTarget
            case .failed(let error):
                throw IntentMessage(error, target: target.address)
            case .started, .name:
                continue
            }
        }
        let summary =
            reached
            ? String(localized: "\(host) reached after \(lines.count) hops")
            : String(localized: "\(host) not reached within \(lines.count) hops")
        return .result(value: lines, dialog: IntentSupport.dialog(summary))
    }
}

struct PathMTUIntent: AppIntent {
    static let title: LocalizedStringResource = "Find the path MTU"
    static let description = IntentDescription(
        "Sends pings that must not be fragmented, of growing size, and returns the largest packet that reaches the host in one piece.")
    static let openAppWhenRun = false

    @Parameter(title: "Host", description: "A host name or IP address", requestValueDialog: "Which host?")
    var host: String

    static var parameterSummary: some ParameterSummary { Summary("Find the path MTU to \(\.$host)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let target = try await IntentSupport.target(host)
        for await event in PathMTUTool.run(address: target.address) {
            switch event {
            case .finished(let mtu):
                guard let mtu else { throw IntentMessage(String(localized: "No packet size got through")) }
                return .result(value: mtu, dialog: IntentSupport.dialog(String(localized: "Path MTU to \(host): \(mtu) bytes")))
            case .failed(let error):
                throw IntentMessage(error, target: target.address)
            case .started, .probe:
                continue
            }
        }
        throw IntentMessage(ToolError.timeout)
    }
}

struct ClockOffsetIntent: AppIntent {
    static let title: LocalizedStringResource = "Check the clock"
    static let description = IntentDescription(
        "Asks a time server how far the device's clock is off. Returns the offset in milliseconds: positive means the device is behind.")
    static let openAppWhenRun = false

    @Parameter(title: "Server", default: "time.apple.com")
    var server: String

    static var parameterSummary: some ParameterSummary { Summary("Check the clock against \(\.$server)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let result: NTPResult
        do {
            result = try await NTPClient.query(host: try ToolInput.host(server))
        } catch {
            throw IntentMessage(error)
        }
        let offset = result.offsetMilliseconds
        let amount = milliseconds(abs(offset))
        let text = offset >= 0 ? String(localized: "\(amount) behind") : String(localized: "\(amount) ahead")
        let rounded = (offset * 10).rounded() / 10
        return .result(value: rounded, dialog: IntentSupport.dialog(String(localized: "Clock: \(text)")))
    }
}
