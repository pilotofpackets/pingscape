import Foundation

/// The public IP address of this device, as an outside server sees it.
///
/// Asks api.ipify.org for IPv4 and api6.ipify.org for IPv6. Two host names
/// with one address family each, so the system does not have to choose. The
/// request carries nothing but the request itself.
public enum PublicIPLookup {
    public enum Version: Sendable {
        case v4, v6

        var address: String {
            switch self {
            case .v4: "https://api.ipify.org"
            case .v6: "https://api6.ipify.org"
            }
        }
    }

    public static let timeoutSeconds = 6.0

    /// The address, or `nil` if the server answered with something that is not
    /// an address of that version. Errors (no connection) are thrown.
    public static func fetch(_ version: Version) async throws -> String? {
        let url = URL(string: version.address)!
        let request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeoutSeconds)
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return validated(String(decoding: data.prefix(64), as: UTF8.self), version: version)
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
