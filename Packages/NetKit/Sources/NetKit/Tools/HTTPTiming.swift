import Foundation
import Synchronization

/// One request in a chain of redirects, with the time each phase took.
/// A phase that did not happen (no TLS on `http://`) is `nil` and its row is left out.
public struct HTTPTimingStep: Sendable, Equatable, Identifiable {
    public let id: Int
    public let url: String
    public let statusCode: Int?
    /// `h2`, `h3`, `http/1.1`
    public let networkProtocol: String?
    public let remoteAddress: String?
    public let remotePort: Int?
    public let dnsMilliseconds: Double?
    public let tcpMilliseconds: Double?
    public let tlsMilliseconds: Double?
    /// From sending the request to the first byte of the answer.
    public let waitMilliseconds: Double?
    /// From the start of the request to the first byte of the answer.
    public let totalMilliseconds: Double?

    public init(
        id: Int, url: String, statusCode: Int?, networkProtocol: String?, remoteAddress: String?, remotePort: Int?,
        dnsMilliseconds: Double?, tcpMilliseconds: Double?, tlsMilliseconds: Double?, waitMilliseconds: Double?,
        totalMilliseconds: Double?
    ) {
        self.id = id
        self.url = url
        self.statusCode = statusCode
        self.networkProtocol = networkProtocol
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.dnsMilliseconds = dnsMilliseconds
        self.tcpMilliseconds = tcpMilliseconds
        self.tlsMilliseconds = tlsMilliseconds
        self.waitMilliseconds = waitMilliseconds
        self.totalMilliseconds = totalMilliseconds
    }
}

/// Measures where the time goes in one HTTPS request. The session is new and
/// has no cache, so DNS, TCP and TLS really happen. Only the headers are
/// read: the body is not loaded.
public enum HTTPTimer {
    public static let timeoutSeconds = 15.0
    public static let maximumRedirects = 10

    /// The address the user typed as a URL: `https://` is added if there is no scheme.
    public static func url(from text: String) throws -> URL {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InputError.empty }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = components.host, !host.isEmpty,
            (try? ToolInput.host(host)) != nil, let url = components.url
        else { throw InputError.invalidURL }
        return url
    }

    public static func measure(_ url: URL) async throws -> [HTTPTimingStep] {
        let collector = Collector()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let task = session.dataTask(with: request)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                collector.begin(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
            session.invalidateAndCancel()
        }
    }

    private final class Collector: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, Sendable {
        struct State {
            var continuation: CheckedContinuation<[HTTPTimingStep], any Error>?
            var metrics: URLSessionTaskMetrics?
            var redirects = 0
            /// We ended the transfer after the headers on purpose.
            var stoppedAfterHeaders = false
        }

        private let state = Mutex(State())

        func begin(_ continuation: CheckedContinuation<[HTTPTimingStep], any Error>) {
            state.withLock { $0.continuation = continuation }
        }

        func urlSession(
            _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            state.withLock { $0.stoppedAfterHeaders = true }
            completionHandler(.cancel)
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            let allowed = state.withLock { state -> Bool in
                state.redirects += 1
                return state.redirects <= HTTPTimer.maximumRedirects
            }
            completionHandler(allowed ? request : nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            state.withLock { $0.metrics = metrics }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            let (continuation, metrics, stopped) = state.withLock { state in
                defer { state.continuation = nil }
                return (state.continuation, state.metrics, state.stoppedAfterHeaders)
            }
            session.finishTasksAndInvalidate()
            let steps = metrics.map(HTTPTimer.steps) ?? []
            if let error, !(stopped && (error as? URLError)?.code == .cancelled) {
                // Whatever was measured before the failure still helps, but the
                // failure is the answer.
                continuation?.resume(throwing: HTTPTimer.map(error))
            } else if steps.isEmpty {
                continuation?.resume(throwing: ToolError.unreadable)
            } else {
                continuation?.resume(returning: steps)
            }
        }
    }

    static func steps(_ metrics: URLSessionTaskMetrics) -> [HTTPTimingStep] {
        metrics.transactionMetrics.enumerated().map { index, transaction in
            func milliseconds(_ start: Date?, _ end: Date?) -> Double? {
                guard let start, let end, end >= start else { return nil }
                return end.timeIntervalSince(start) * 1000
            }
            // The system counts the TLS handshake as part of "connect".
            let tcpEnd = transaction.secureConnectionStartDate ?? transaction.connectEndDate
            return HTTPTimingStep(
                id: index,
                url: transaction.request.url?.absoluteString ?? "",
                statusCode: (transaction.response as? HTTPURLResponse)?.statusCode,
                networkProtocol: transaction.networkProtocolName,
                remoteAddress: transaction.remoteAddress,
                remotePort: transaction.remotePort,
                dnsMilliseconds: milliseconds(transaction.domainLookupStartDate, transaction.domainLookupEndDate),
                tcpMilliseconds: milliseconds(transaction.connectStartDate, tcpEnd),
                tlsMilliseconds: milliseconds(transaction.secureConnectionStartDate, transaction.secureConnectionEndDate),
                waitMilliseconds: milliseconds(transaction.requestStartDate, transaction.responseStartDate),
                totalMilliseconds: milliseconds(transaction.fetchStartDate, transaction.responseStartDate))
        }
    }

    static func map(_ error: any Error) -> ToolError {
        guard let error = error as? URLError else { return .failed(error.localizedDescription) }
        switch error.code {
        case .timedOut: return .timeout
        case .cannotFindHost, .dnsLookupFailed: return .cannotResolve
        case .cannotConnectToHost: return .refused
        case .notConnectedToInternet, .networkConnectionLost, .internationalRoamingOff: return .noRoute
        case .appTransportSecurityRequiresSecureConnection: return .insecureConnection
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
            .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
            return .handshakeFailed
        default: return .failed(error.localizedDescription)
        }
    }
}
