import Foundation
import Network
import Security
import Synchronization

/// The system's verdict on a certificate chain.
public enum TLSTrust: Sendable, Equatable {
    case trusted
    /// The system did not trust the chain. The text is the system's own reason.
    case untrusted(String)
}

public struct TLSReport: Sendable, Equatable {
    public let host: String
    public let port: UInt16
    /// The address the handshake went to.
    public let remoteAddress: String?
    /// `TLS 1.3`
    public let protocolVersion: String?
    public let cipherSuite: String?
    /// From the server's certificate to the top of the chain it sent.
    public let chain: [CertificateInfo]
    public let trust: TLSTrust

    public init(
        host: String, port: UInt16, remoteAddress: String?, protocolVersion: String?, cipherSuite: String?,
        chain: [CertificateInfo], trust: TLSTrust
    ) {
        self.host = host
        self.port = port
        self.remoteAddress = remoteAddress
        self.protocolVersion = protocolVersion
        self.cipherSuite = cipherSuite
        self.chain = chain
        self.trust = trust
    }
}

/// Does a TLS handshake and reads what the server presents. Only the
/// handshake happens, no data is sent or received.
///
/// The connection accepts any certificate on purpose: the tool is there to
/// show what the server presents, also when it is expired or untrusted. The
/// verdict comes from the system's own evaluation (`SecTrust`), reported
/// separately in `TLSReport.trust`.
public enum TLSInspector {
    public static let timeoutSeconds = 6.0

    private final class Capture: Sendable {
        struct Value {
            var chain: [CertificateInfo] = []
            var trust: TLSTrust?
        }

        let value = Mutex(Value())
    }

    private final class Once: Sendable {
        let state = Mutex<CheckedContinuation<TLSReport, any Error>?>(nil)

        func set(_ continuation: CheckedContinuation<TLSReport, any Error>) {
            state.withLock { $0 = continuation }
        }

        func finish(_ result: Result<TLSReport, any Error>) {
            let continuation = state.withLock { state -> CheckedContinuation<TLSReport, any Error>? in
                defer { state = nil }
                return state
            }
            continuation?.resume(with: result)
        }
    }

    public static func inspect(host: String, port: UInt16 = 443) async throws -> TLSReport {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw InputError.invalidPort }
        let capture = Capture()
        let options = NWProtocolTLS.Options()
        if !ToolInput.isIPv4(host) && !ToolInput.isIPv6(host) {
            sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, host)
        }
        sec_protocol_options_set_verify_block(
            options.securityProtocolOptions,
            { _, trust, complete in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                var error: CFError?
                let trusted = SecTrustEvaluateWithError(secTrust, &error)
                let certificates = (SecTrustCopyCertificateChain(secTrust) as? [SecCertificate]) ?? []
                let infos = certificates.compactMap { certificate -> CertificateInfo? in
                    X509.parse(der: [UInt8](SecCertificateCopyData(certificate) as Data))
                }
                capture.value.withLock {
                    $0.chain = infos
                    $0.trust = trusted ? .trusted : .untrusted((error as Error?)?.localizedDescription ?? "")
                }
                complete(true)
            }, DispatchQueue(label: "app.pingscape.tls.verify"))

        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: endpointPort,
            using: NWParameters(tls: options, tcp: NWProtocolTCP.Options()))
        let once = Once()
        let queue = DispatchQueue(label: "app.pingscape.tls")

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.set(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        once.finish(.success(report(connection, host: host, port: port, capture: capture)))
                        connection.cancel()
                    case .failed(let error):
                        once.finish(.failure(map(error)))
                        connection.cancel()
                    case .waiting(let error):
                        // Refused, unreachable and an unknown name will not fix
                        // themselves in the time limit.
                        switch error {
                        case .posix, .dns:
                            once.finish(.failure(map(error)))
                            connection.cancel()
                        default:
                            break
                        }
                    case .cancelled:
                        once.finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                    once.finish(.failure(ToolError.timeout))
                    connection.cancel()
                }
            }
        } onCancel: {
            once.finish(.failure(CancellationError()))
            connection.cancel()
        }
    }

    private static func report(_ connection: NWConnection, host: String, port: UInt16, capture: Capture) -> TLSReport {
        var version: String?
        var suite: String?
        if let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
            let security = metadata.securityProtocolMetadata
            version = versionName(sec_protocol_metadata_get_negotiated_tls_protocol_version(security))
            suite = cipherSuiteName(sec_protocol_metadata_get_negotiated_tls_ciphersuite(security))
        }
        var remote: String?
        if case .hostPort(let address, _)? = connection.currentPath?.remoteEndpoint {
            remote = "\(address)".split(separator: "%").first.map(String.init)
        }
        let captured = capture.value.withLock { $0 }
        return TLSReport(
            host: host, port: port, remoteAddress: remote, protocolVersion: version, cipherSuite: suite,
            chain: captured.chain, trust: captured.trust ?? .untrusted(""))
    }

    private static func map(_ error: NWError) -> ToolError {
        switch error {
        case .posix(let code): ToolError(errno: code.rawValue)
        case .dns: .cannotResolve
        case .tls: .handshakeFailed
        default: .failed("\(error)")
        }
    }

    static func versionName(_ version: tls_protocol_version_t) -> String? {
        switch version {
        case .TLSv10: "TLS 1.0"
        case .TLSv11: "TLS 1.1"
        case .TLSv12: "TLS 1.2"
        case .TLSv13: "TLS 1.3"
        default: nil
        }
    }

    /// The IANA names of the cipher suites a current server negotiates.
    static func cipherSuiteName(_ suite: tls_ciphersuite_t) -> String {
        let names: [UInt16: String] = [
            0x1301: "TLS_AES_128_GCM_SHA256", 0x1302: "TLS_AES_256_GCM_SHA384",
            0x1303: "TLS_CHACHA20_POLY1305_SHA256",
            0xC02B: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", 0xC02C: "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
            0xC02F: "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", 0xC030: "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
            0xCCA8: "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256",
            0xCCA9: "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
            0x009C: "TLS_RSA_WITH_AES_128_GCM_SHA256", 0x009D: "TLS_RSA_WITH_AES_256_GCM_SHA384",
        ]
        return names[suite.rawValue] ?? String(format: "0x%04X", suite.rawValue)
    }
}
