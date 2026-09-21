import Foundation
import NetKit
import Observation

// Each tool has a model that runs the work and keeps the result. Results live
// only in memory, so switching tools does not lose them, and quitting the app does.

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: Ping

struct PingLine: Identifiable, Equatable {
    enum Kind: Equatable {
        case reply(bytes: Int?, milliseconds: Double, ttl: Int?)
        case noReply
        case failed(ToolError)
    }

    let id: Int
    let kind: Kind
}

@MainActor
@Observable
final class PingModel: ToolControl {
    var input = ""
    private(set) var isRunning = false
    private(set) var failure: ToolFailure?
    private(set) var addresses: [ResolvedAddress] = []
    private(set) var current: ResolvedAddress?
    private(set) var method: PingMethod?
    private(set) var lines: [PingLine] = []
    private(set) var statistics = PingStatistics()
    private var task: Task<Void, Never>?

    /// At most this many replies stay in memory. The oldest fall out.
    private static let capacity = 1000

    var inputText: String { input }
    var canStart: Bool { !input.trimmed.isEmpty }

    /// The choice IPv4 / IPv6 appears only when the name has both.
    var offersFamilyChoice: Bool {
        addresses.contains(where: \.isIPv6) && addresses.contains(where: { !$0.isIPv6 })
    }

    func start() {
        stop()
        failure = nil
        let host: String
        do { host = try ToolInput.host(input) } catch let error as InputError {
            failure = .input(error)
            return
        } catch { return }
        isRunning = true
        lines = []
        statistics = PingStatistics()
        addresses = []
        current = nil
        method = nil
        task = Task {
            do {
                addresses = try await HostResolver.resolve(host)
            } catch { return }
            guard let first = addresses.first else {
                failure = .tool(.cannotResolve)
                isRunning = false
                return
            }
            await run(first)
        }
    }

    func select(ipv6: Bool) {
        guard let address = addresses.first(where: { $0.isIPv6 == ipv6 }), address != current else { return }
        task?.cancel()
        isRunning = true
        lines = []
        statistics = PingStatistics()
        failure = nil
        task = Task { await run(address) }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func run(_ address: ResolvedAddress) async {
        current = address
        for await event in PingTool.run(address: address) {
            switch event {
            case .started(_, let started):
                method = started
            case .reply(let sequence, let bytes, let milliseconds, let ttl):
                statistics.recordReply(milliseconds: milliseconds)
                append(PingLine(id: sequence, kind: .reply(bytes: bytes, milliseconds: milliseconds, ttl: ttl)))
            case .noReply(let sequence):
                statistics.recordLoss()
                append(PingLine(id: sequence, kind: .noReply))
            case .failed(let sequence, let error):
                statistics.recordLoss()
                failure = .from(error, target: address)
                append(PingLine(id: sequence, kind: .failed(error)))
            }
        }
        if !Task.isCancelled { isRunning = false }
    }

    private func append(_ line: PingLine) {
        lines.append(line)
        if lines.count > Self.capacity { lines.removeFirst(lines.count - Self.capacity) }
    }

    static func demo() -> PingModel {
        let model = PingModel()
        model.input = "one.one.one.one"
        model.current = ResolvedAddress(literal: "1.1.1.1")
        model.addresses = [model.current!, ResolvedAddress(literal: "2606:4700:4700::1111")!]
        model.method = .icmp
        for (index, value) in [12.8, 13.1, 12.6, 14.0, 12.9].enumerated() {
            model.statistics.recordReply(milliseconds: value)
            model.lines.append(PingLine(id: index + 1, kind: .reply(bytes: 84, milliseconds: value, ttl: 59)))
        }
        model.statistics.recordLoss()
        model.lines.append(PingLine(id: 6, kind: .noReply))
        return model
    }
}

// MARK: Traceroute

@MainActor
@Observable
final class TracerouteModel: ToolControl {
    var input = ""
    var resolveNames = true
    private(set) var isRunning = false
    private(set) var failure: ToolFailure?
    private(set) var address: ResolvedAddress?
    private(set) var hops: [TracerouteHop] = []
    private(set) var names: [Int: String] = [:]
    /// `nil` while running or before a run.
    private(set) var reachedTarget: Bool?
    private var task: Task<Void, Never>?

    var inputText: String { input }
    var canStart: Bool { !input.trimmed.isEmpty }

    func start() {
        stop()
        failure = nil
        let host: String
        do { host = try ToolInput.host(input) } catch let error as InputError {
            failure = .input(error)
            return
        } catch { return }
        isRunning = true
        hops = []
        names = [:]
        reachedTarget = nil
        address = nil
        let resolveNames = resolveNames
        task = Task {
            guard let target = (try? await HostResolver.resolve(host))?.first else {
                if !Task.isCancelled { failure = .tool(.cannotResolve) }
                isRunning = false
                return
            }
            address = target
            var settings = TracerouteSettings()
            settings.resolveNames = resolveNames
            for await event in TracerouteTool.run(address: target, settings: settings) {
                switch event {
                case .started: break
                case .hop(let hop): hops.append(hop)
                case .name(let hop, let name): names[hop] = name
                case .finished(let reached): reachedTarget = reached
                case .failed(let error): failure = .from(error, target: target)
                }
            }
            if !Task.isCancelled { isRunning = false }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    static func demo() -> TracerouteModel {
        let model = TracerouteModel()
        model.input = "one.one.one.one"
        model.address = ResolvedAddress(literal: "1.1.1.1")
        model.hops = [
            TracerouteHop(number: 1, address: "192.168.178.1", times: [2.4, 2.1, 2.3]),
            TracerouteHop(number: 2, address: "203.0.113.1", times: [9.2, 9.3, 9.1]),
            TracerouteHop(number: 3, address: nil, times: [nil, nil, nil]),
            TracerouteHop(number: 4, address: "198.51.100.14", times: [12.5, 12.3, 12.6]),
            TracerouteHop(number: 5, address: "1.1.1.1", times: [12.9, 12.6, 13.0]),
        ]
        model.names = [1: "fritz.box", 2: "edge1.example.net", 5: "one.one.one.one"]
        model.reachedTarget = true
        return model
    }
}

// MARK: DNS

enum DNSServerChoice: Hashable, CaseIterable {
    case system, cloudflare, google, quad9, custom

    var address: String? {
        switch self {
        case .cloudflare: "1.1.1.1"
        case .google: "8.8.8.8"
        case .quad9: "9.9.9.9"
        default: nil
        }
    }
}

@MainActor
@Observable
final class DNSModel: ToolControl {
    var input = ""
    var type: DNSRecordType = .a
    var choice: DNSServerChoice = .system
    var customServer = ""
    /// The DNS servers of the current network or VPN, kept up to date by the view.
    var systemServers: [String] = []
    private(set) var isRunning = false
    private(set) var failure: ToolFailure?
    private(set) var response: DNSResponse?
    private var task: Task<Void, Never>?

    var inputText: String { input }
    var canStart: Bool { !input.trimmed.isEmpty }

    /// The server the next request goes to, for the line above the button.
    var serverText: String? {
        switch choice {
        case .system: systemServers.first
        case .custom: customServer.trimmed.isEmpty ? nil : customServer.trimmed
        default: choice.address
        }
    }

    func start() {
        stop()
        failure = nil
        response = nil
        let text = input.trimmed
        let isReverse = type == .ptr && (ToolInput.isIPv4(text) || ToolInput.isIPv6(text))
        let name: String
        do { name = isReverse ? text : try ToolInput.host(text, allowUnderscore: true) } catch let error as InputError {
            failure = .input(error)
            return
        } catch { return }
        guard let serverText, let server = ResolvedAddress(literal: serverText) else {
            failure = choice == .custom ? .input(.invalidHost) : .tool(.noRoute)
            return
        }
        let type = type
        isRunning = true
        task = Task {
            do {
                response =
                    isReverse
                    ? try await DNSClient.reverse(ip: name, server: server)
                    : try await DNSClient.query(name: name, type: type, server: server)
            } catch is CancellationError {
                return
            } catch let error as InputError {
                failure = .input(error)
            } catch let error as ToolError {
                failure = .from(error, target: server)
            } catch {
                failure = .tool(.unreadable)
            }
            if !Task.isCancelled { isRunning = false }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    static func demo() -> DNSModel {
        let model = DNSModel()
        model.input = "example.com"
        model.type = .mx
        model.choice = .cloudflare
        model.response = DNSResponse(
            server: "1.1.1.1", transport: .udp, responseCode: 0, responseCodeName: "NOERROR", flags: ["RD", "RA"],
            answers: [
                DNSRecord(name: "example.com", type: "MX", ttl: 3600, value: "10 mail.example.com"),
                DNSRecord(name: "example.com", type: "MX", ttl: 3600, value: "20 backup.example.com"),
            ],
            milliseconds: 13)
        return model
    }
}

// MARK: Whois and RDAP

@MainActor
@Observable
final class WhoisModel: ToolControl {
    var input = ""
    private(set) var isRunning = false
    private(set) var failure: ToolFailure?
    private(set) var whois: [WhoisStep] = []
    private(set) var whoisFailure: ToolFailure?
    private(set) var rdap: RDAPResult?
    private(set) var rdapFailure: ToolFailure?
    private(set) var hasResult = false
    private var task: Task<Void, Never>?

    var inputText: String { input }
    var canStart: Bool { !input.trimmed.isEmpty }

    func start() {
        stop()
        failure = nil
        whois = []
        rdap = nil
        whoisFailure = nil
        rdapFailure = nil
        hasResult = false
        let target: LookupTarget
        do { target = try LookupTarget(input) } catch let error as InputError {
            failure = .input(error)
            return
        } catch { return }
        isRunning = true
        task = Task {
            async let rdapResult = Self.fetchRDAP(target)
            async let whoisResult = Self.fetchWhois(target)
            let (rdapAnswer, whoisAnswer) = await (rdapResult, whoisResult)
            guard !Task.isCancelled else { return }
            switch rdapAnswer {
            case .success(let result): rdap = result
            case .failure(let error): rdapFailure = .tool(error)
            }
            switch whoisAnswer {
            case .success(let steps): whois = steps
            case .failure(let error): whoisFailure = .tool(error)
            }
            hasResult = true
            isRunning = false
        }
    }

    private nonisolated static func fetchRDAP(_ target: LookupTarget) async -> Result<RDAPResult, ToolError> {
        do { return .success(try await RDAPClient.lookup(target)) } catch let error as ToolError {
            return .failure(error)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    private nonisolated static func fetchWhois(_ target: LookupTarget) async -> Result<[WhoisStep], ToolError> {
        do { return .success(try await WhoisClient.lookup(target)) } catch let error as ToolError {
            return .failure(error)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    static func demo() -> WhoisModel {
        let model = WhoisModel()
        model.input = "example.com"
        model.rdap = RDAPResult(
            server: "rdap.verisign.com", name: "EXAMPLE.COM", handle: "2336799_DOMAIN_COM-VRSN",
            status: ["client delete prohibited", "client transfer prohibited"],
            registrar: "Example Registrar, Inc.",
            events: [
                RDAPEvent(action: .registration, date: "1995-08-14T04:00:00Z"),
                RDAPEvent(action: .lastChanged, date: "2026-08-14T08:01:43Z"),
                RDAPEvent(action: .expiration, date: "2027-08-13T04:00:00Z"),
            ],
            nameservers: ["A.IANA-SERVERS.NET", "B.IANA-SERVERS.NET"], range: nil)
        model.whois = [
            WhoisStep(server: "whois.iana.org", text: "domain:       COM\norganisation: VeriSign Global Registry Services\nrefer:        whois.verisign-grs.com"),
            WhoisStep(server: "whois.verisign-grs.com", text: "   Domain Name: EXAMPLE.COM\n   Registry Domain ID: 2336799_DOMAIN_COM-VRSN\n   Registrar: Example Registrar, Inc."),
        ]
        model.hasResult = true
        return model
    }
}

// MARK: Ports

struct OpenPort: Identifiable, Equatable {
    var id: Int { port }
    let port: Int
    let milliseconds: Double?
}

@MainActor
@Observable
final class PortsModel: ToolControl {
    var input = ""
    var portsText = ""
    var useCommonPorts = true
    /// Whether the target is outside the private address ranges. `nil` while unknown.
    private(set) var targetIsForeign: Bool?
    private(set) var isRunning = false
    private(set) var failure: ToolFailure?
    private(set) var address: ResolvedAddress?
    private(set) var open: [OpenPort] = []
    private(set) var closedCount = 0
    private(set) var noResponseCount = 0
    private(set) var progress: (done: Int, total: Int)?
    private var task: Task<Void, Never>?
    private var classifyTask: Task<Void, Never>?

    var inputText: String { input }
    var canStart: Bool { !input.trimmed.isEmpty && (useCommonPorts || targetIsForeign == true || !portsText.trimmed.isEmpty) }

    /// A foreign target is only scanned with the common ports.
    var portsAreLocked: Bool { targetIsForeign == true }

    /// Looks at the target while the user types, to warn before the start.
    func classify() {
        classifyTask?.cancel()
        targetIsForeign = nil
        guard let host = try? ToolInput.host(input) else { return }
        classifyTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            if let literal = ResolvedAddress(literal: host) {
                targetIsForeign = !literal.isLocal
                return
            }
            guard let first = (try? await HostResolver.resolve(host))?.first, !Task.isCancelled else { return }
            targetIsForeign = !first.isLocal
        }
    }

    func start() {
        stop()
        failure = nil
        open = []
        closedCount = 0
        noResponseCount = 0
        progress = nil
        let host: String
        let ports: [Int]
        do {
            host = try ToolInput.host(input)
            ports = useCommonPorts || portsAreLocked ? PortScanner.commonPorts : try PortList.parse(portsText)
        } catch let error as InputError {
            failure = .input(error)
            return
        } catch { return }
        isRunning = true
        task = Task {
            guard let target = (try? await HostResolver.resolve(host))?.first else {
                if !Task.isCancelled { failure = .tool(.cannotResolve) }
                isRunning = false
                return
            }
            address = target
            targetIsForeign = !target.isLocal
            for await event in PortScanner.run(address: target, ports: ports) {
                switch event {
                case .started: break
                case .result(let port, let state, let milliseconds):
                    switch state {
                    case .open: open.append(OpenPort(port: port, milliseconds: milliseconds))
                    case .closed: closedCount += 1
                    case .noResponse: noResponseCount += 1
                    }
                case .progress(let done, let total): progress = (done, total)
                case .failed(let error): failure = .from(error, target: target)
                case .finished: break
                }
            }
            open.sort { $0.port < $1.port }
            if !Task.isCancelled { isRunning = false }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    static func demo() -> PortsModel {
        let model = PortsModel()
        model.input = "192.168.178.1"
        model.address = ResolvedAddress(literal: "192.168.178.1")
        model.targetIsForeign = false
        model.open = [OpenPort(port: 53, milliseconds: 2), OpenPort(port: 80, milliseconds: 3), OpenPort(port: 443, milliseconds: 3)]
        model.closedCount = 60
        model.noResponseCount = 4
        model.progress = (67, 67)
        return model
    }
}

// MARK: TLS

@MainActor
@Observable
final class TLSModel: ToolControl {
    var input = ""
    private(set) var isRunning = false
    private(set) var failure: ToolFailure?
    private(set) var report: TLSReport?
    private var task: Task<Void, Never>?

    var inputText: String { input }
    var canStart: Bool { !input.trimmed.isEmpty }

    func start() {
        stop()
        failure = nil
        report = nil
        let parsed: (host: String, port: UInt16?)
        do { parsed = try ToolInput.hostAndPort(input, defaultPort: 443) } catch let error as InputError {
            failure = .input(error)
            return
        } catch { return }
        isRunning = true
        task = Task {
            do {
                report = try await TLSInspector.inspect(host: parsed.host, port: parsed.port ?? 443)
            } catch is CancellationError {
                return
            } catch let error as ToolError {
                failure = .from(error, target: ResolvedAddress(literal: parsed.host))
            } catch {
                failure = .tool(.handshakeFailed)
            }
            if !Task.isCancelled { isRunning = false }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    static func demo() -> TLSModel {
        let model = TLSModel()
        model.input = "example.com"
        let now = Date()
        model.report = TLSReport(
            host: "example.com", port: 443, remoteAddress: "93.184.216.34", protocolVersion: "TLS 1.3",
            cipherSuite: "TLS_AES_256_GCM_SHA384",
            chain: [
                CertificateInfo(
                    subjectName: "example.com", subjectOrganization: nil, issuerName: "Example Intermediate CA",
                    issuerOrganization: "Example Trust", notBefore: now.addingTimeInterval(-60 * 86_400),
                    notAfter: now.addingTimeInterval(36 * 86_400), serialNumber: "0A:1B:2C:3D",
                    alternativeNames: ["example.com", "www.example.com"]),
                CertificateInfo(
                    subjectName: "Example Intermediate CA", subjectOrganization: "Example Trust",
                    issuerName: "Example Root CA", issuerOrganization: "Example Trust",
                    notBefore: now.addingTimeInterval(-900 * 86_400), notAfter: now.addingTimeInterval(3_000 * 86_400),
                    serialNumber: "01", alternativeNames: []),
            ],
            trust: .trusted)
        return model
    }
}

// MARK: HTTP timing

@MainActor
@Observable
final class HTTPModel: ToolControl {
    var input = ""
    private(set) var isRunning = false
    private(set) var failure: ToolFailure?
    private(set) var steps: [HTTPTimingStep] = []
    private var task: Task<Void, Never>?

    var inputText: String { input }
    var canStart: Bool { !input.trimmed.isEmpty }

    func start() {
        stop()
        failure = nil
        steps = []
        let url: URL
        do { url = try HTTPTimer.url(from: input) } catch let error as InputError {
            failure = .input(error)
            return
        } catch { return }
        isRunning = true
        task = Task {
            do {
                steps = try await HTTPTimer.measure(url)
            } catch is CancellationError {
                return
            } catch let error as ToolError {
                failure = .tool(error)
            } catch {
                failure = .tool(.failed(error.localizedDescription))
            }
            if !Task.isCancelled { isRunning = false }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    static func demo() -> HTTPModel {
        let model = HTTPModel()
        model.input = "example.com"
        model.steps = [
            HTTPTimingStep(
                id: 0, url: "http://example.com/", statusCode: 301, networkProtocol: "http/1.1",
                remoteAddress: "93.184.216.34", remotePort: 80, dnsMilliseconds: 14, tcpMilliseconds: 21,
                tlsMilliseconds: nil, waitMilliseconds: 24, totalMilliseconds: 61),
            HTTPTimingStep(
                id: 1, url: "https://example.com/", statusCode: 200, networkProtocol: "h2",
                remoteAddress: "93.184.216.34", remotePort: 443, dnsMilliseconds: 0.5, tcpMilliseconds: 20,
                tlsMilliseconds: 31, waitMilliseconds: 30, totalMilliseconds: 82),
        ]
        return model
    }
}
