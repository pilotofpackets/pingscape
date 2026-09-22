import Foundation
import Network

extension PublicIPLookup.Version {
    /// `api.ipify.org` or `api6.ipify.org`, without the scheme.
    var host: String {
        switch self {
        case .v4: "api.ipify.org"
        case .v6: "api6.ipify.org"
        }
    }
}

extension PublicIPLookup {
    /// The public address as this device's traffic looks from one specific
    /// interface, bypassing a VPN that would otherwise carry it (a full
    /// tunnel routes everything through itself; binding to Wi-Fi's or
    /// cellular's own interface sends this one request around it, so the
    /// underlying connection's own address can still be shown next to it).
    ///
    /// `URLSession` has no public way to bind a request to one interface, so
    /// this sends a minimal HTTP/1.1 request by hand over `NWConnection`,
    /// bound with `requiredInterface`. Same building block as `TLSInspector`,
    /// which does the handshake the same way; here the request is also sent
    /// and its small plain-text body is read.
    public static func fetch(_ version: Version, over interface: NWInterface) async throws -> String? {
        let data = try await response(host: version.host, interface: interface)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard let headerEnd = text.range(of: "\r\n\r\n") else { return nil }
        let statusLine = text[text.startIndex..<(text.firstIndex(of: "\r") ?? text.endIndex)]
        guard statusLine.contains(" 200 ") else { return nil }
        return validated(String(text[headerEnd.upperBound...]), version: version)
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, any Error>?

        func set(_ continuation: CheckedContinuation<Data, any Error>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func finish(_ result: Result<Data, any Error>) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
        }
    }

    private static func response(host: String, interface: NWInterface) async throws -> Data {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, host)
        let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        parameters.requiredInterface = interface
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 443, using: parameters)
        let request = Data("GET / HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\nUser-Agent: Pingscape\r\n\r\n".utf8)
        let once = Once()
        let queue = DispatchQueue(label: "app.pingscape.publicip.bound")

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                once.set(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.send(
                            content: request,
                            completion: .contentProcessed { error in
                                if let error {
                                    once.finish(.failure(map(error)))
                                    connection.cancel()
                                    return
                                }
                                receive(connection, buffer: Data(), once: once)
                            })
                    case .failed(let error):
                        once.finish(.failure(map(error)))
                        connection.cancel()
                    case .waiting(let error):
                        // A wrong interface (no route, no address on it) will
                        // not fix itself in the time limit.
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

    /// The address of ipify never comes close to this; it is only a backstop
    /// against a connection that never signals `isComplete`.
    private static let maxResponseBytes = 1 << 16

    private static func receive(_ connection: NWConnection, buffer: Data, once: Once) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let error {
                once.finish(.failure(map(error)))
                connection.cancel()
                return
            }
            if isComplete || buffer.count >= maxResponseBytes {
                once.finish(.success(buffer))
                connection.cancel()
                return
            }
            receive(connection, buffer: buffer, once: once)
        }
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
