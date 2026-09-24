import Foundation

/// The public IP address of this device, as an outside server sees it.
///
/// Asks api.ipify.org for IPv4 and api6.ipify.org for IPv6, and if that host
/// does not answer, icanhazip.com next (`Version.hosts`). Each host splits
/// IPv4 and IPv6 onto its own name, so the system never has to choose. The
/// request carries nothing but the request itself.
public enum PublicIPLookup {
    public enum Version: Sendable {
        case v4, v6
    }

    public static let timeoutSeconds = 6.0

    /// The address, or `nil` if every host answered with something that is
    /// not an address of that version. Errors (no connection, a non-200
    /// status) are thrown as a `ToolError`, so the caller can show why the
    /// last host it tried failed.
    public static func fetch(_ version: Version) async throws -> String? {
        var lastError: ToolError?
        for host in version.hosts {
            do {
                if let address = try await fetch(version, host: host) { return address }
            } catch let error as ToolError {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return nil
    }

    private static func fetch(_ version: Version, host: String) async throws -> String? {
        let url = URL(string: "https://\(host)")!
        let request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeoutSeconds)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        } catch {
            throw map(error)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        guard status == 200 else { throw ToolError.failed("HTTP \(status)") }
        return validated(String(decoding: data.prefix(64), as: UTF8.self), version: version)
    }

    /// `URLSession` throws `URLError`/`NSError`, not `ToolError`; map the
    /// codes that can happen for a plain HTTPS request to one host.
    private static func map(_ error: any Error) -> ToolError {
        switch (error as NSError).code {
        case NSURLErrorTimedOut: .timeout
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: .cannotResolve
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost: .refused
        case NSURLErrorNotConnectedToInternet, NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed:
            .noRoute
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted: .handshakeFailed
        default: .failed((error as NSError).localizedDescription)
        }
    }

    static func validated(_ text: String, version: Version) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch version {
        case .v4: return ToolInput.isIPv4(trimmed) ? trimmed : nil
        case .v6: return ToolInput.isIPv6(trimmed) ? trimmed : nil
        }
    }
}

/// Whether the internet is reachable and whether something intercepts it.
public enum InternetCheck: Sendable, Equatable {
    case reachable
    /// A sign-in page answered instead of the internet.
    case captivePortal
    case unreachable

    /// The probe Apple devices use: a page that answers with "Success".
    static let probeURL = URL(string: "http://captive.apple.com/hotspot-detect.html")!

    public static func run() async -> InternetCheck {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(from: probeURL)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return classify(status: status, body: String(decoding: data.prefix(4096), as: UTF8.self))
        } catch {
            return .unreachable
        }
    }

    static func classify(status: Int, body: String) -> InternetCheck {
        if status == 200, body.contains("Success") { return .reachable }
        // A redirect or another page: something answers in place of Apple.
        return .captivePortal
    }

    /// Does not follow redirects, so a portal shows up as a redirect.
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
