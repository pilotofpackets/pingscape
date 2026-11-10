import Foundation
import Network
import Synchronization

/// Where a DNS query goes: a plain server (UDP, TCP when the answer does not
/// fit), DNS over TLS (RFC 7858) or DNS over HTTPS (RFC 8484).
public enum DNSEndpoint: Sendable, Equatable {
    case plain(ResolvedAddress)
    /// Port 853. The certificate is checked against `host`, a name or an address.
    case tls(host: String)
    case https(URL)

    /// The address, host or URL, for the line about where the request goes.
    public var text: String {
        switch self {
        case .plain(let address): address.text
        case .tls(let host): "\(host):853"
        case .https(let url): url.absoluteString
        }
    }

    /// DNS over TLS and HTTPS of a public resolver, by its plain address.
    public static func encrypted(publicServer address: String) -> (tlsHost: String, url: URL)? {
        switch address {
        case "1.1.1.1": ("one.one.one.one", URL(string: "https://cloudflare-dns.com/dns-query")!)
        case "8.8.8.8": ("dns.google", URL(string: "https://dns.google/dns-query")!)
        case "9.9.9.9": ("dns.quad9.net", URL(string: "https://dns.quad9.net/dns-query")!)
        default: nil
        }
    }

    /// The DNS over HTTPS address of a server someone typed: a full URL as
    /// it is, a host name or address with the usual path `/dns-query`.
    public static func httpsURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("https://") {
            guard let url = URL(string: trimmed), url.host() != nil else { return nil }
            return url
        }
        guard let host = try? ToolInput.host(trimmed) else { return nil }
        let bracketed = ToolInput.isIPv6(host) ? "[\(host)]" : host
        return URL(string: "https://\(bracketed)/dns-query")
    }
}

/// Encrypted DNS exchanges. Each query opens its own connection, so its time
/// includes the TCP and TLS handshakes, as a first query after joining a
/// network does.
enum EncryptedDNS {
    private final class Once: Sendable {
        let state = Mutex<CheckedContinuation<[UInt8], any Error>?>(nil)

        func set(_ continuation: CheckedContinuation<[UInt8], any Error>) {
            state.withLock { $0 = continuation }
        }

        func finish(_ result: Result<[UInt8], any Error>) {
            let continuation = state.withLock { state -> CheckedContinuation<[UInt8], any Error>? in
                defer { state = nil }
                return state
            }
            continuation?.resume(with: result)
        }
    }

    /// One query over TLS: two length bytes, then the message, both ways.
    static func overTLS(_ packet: [UInt8], host: String, timeoutMilliseconds: Int) async throws -> [UInt8] {
        let options = NWProtocolTLS.Options()
        if !ToolInput.isIPv4(host) && !ToolInput.isIPv6(host) {
            sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, host)
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: 853, using: NWParameters(tls: options, tcp: NWProtocolTCP.Options()))
        let once = Once()
        let queue = DispatchQueue(label: "app.pingscape.dns.tls")
        let framed = Data([UInt8(packet.count >> 8), UInt8(packet.count & 0xFF)] + packet)

        @Sendable func fail(_ error: any Error) {
            once.finish(.failure(error))
            connection.cancel()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.set(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.send(content: framed, completion: .contentProcessed { error in
                            if let error { fail(map(error)) }
                        })
                        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { header, _, _, error in
                            guard let header, header.count == 2, error == nil else {
                                return fail(error.map(map) ?? ToolError.unreadable)
                            }
                            let length = Int(header[header.startIndex]) << 8 | Int(header[header.startIndex + 1])
                            connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                                guard let body, body.count == length, error == nil else {
                                    return fail(error.map(map) ?? ToolError.unreadable)
                                }
                                once.finish(.success([UInt8](body)))
                                connection.cancel()
                            }
                        }
                    case .failed(let error):
                        fail(map(error))
                    case .waiting(let error):
                        switch error {
                        case .posix, .dns, .tls: fail(map(error))
                        default: break
                        }
                    case .cancelled:
                        once.finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMilliseconds)) { fail(ToolError.timeout) }
            }
        } onCancel: {
            fail(CancellationError())
        }
    }

    /// One query over HTTPS, as a POST of the wire format message.
    static func overHTTPS(_ packet: [UInt8], url: URL, timeoutMilliseconds: Int) async throws -> [UInt8] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Double(timeoutMilliseconds) / 1000
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        request.httpBody = Data(packet)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw ToolError.timeout
            case .cannotFindHost, .dnsLookupFailed: throw ToolError.cannotResolve
            case .cannotConnectToHost: throw ToolError.refused
            case .notConnectedToInternet, .networkConnectionLost: throw ToolError.noRoute
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
                throw ToolError.handshakeFailed
            case .cancelled: throw CancellationError()
            default: throw ToolError.failed(error.localizedDescription)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw ToolError.unreadable }
        guard http.statusCode == 200 else { throw ToolError.failed("HTTP \(http.statusCode)") }
        return [UInt8](data)
    }

    private static func map(_ error: NWError) -> ToolError {
        switch error {
        case .posix(let code): ToolError(errno: code.rawValue)
        case .dns: .cannotResolve
        case .tls: .handshakeFailed
        default: .failed("\(error)")
        }
    }
}
