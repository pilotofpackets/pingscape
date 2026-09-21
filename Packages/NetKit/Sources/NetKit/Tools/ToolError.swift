import Darwin

/// Why a tool run or one probe failed. Plain facts, no interpretation. The app
/// turns each case into one short line.
public enum ToolError: Error, Sendable, Equatable {
    /// The name has no address.
    case cannotResolve
    /// No answer within the time limit.
    case timeout
    /// The target answered and refused the connection.
    case refused
    /// The device has no route to the target network.
    case noRoute
    /// The system did not let the app send. For a target in the local network
    /// this is what a refused Local Network permission looks like.
    case notPermitted
    /// RDAP has no server for this name or address.
    case noRegistry
    /// The server answered, but the answer could not be read.
    case unreadable
    /// The TLS handshake did not complete (no shared protocol or cipher, not a TLS server).
    case handshakeFailed
    /// Plain HTTP to an internet host, which the system does not allow apps to do.
    case insecureConnection
    /// The system reported something else. The text comes from the system.
    case failed(String)

    /// Maps a POSIX error number.
    init(errno code: Int32) {
        switch code {
        case ECONNREFUSED: self = .refused
        case ETIMEDOUT: self = .timeout
        case ENETUNREACH, EHOSTUNREACH, ENETDOWN, EHOSTDOWN, EADDRNOTAVAIL: self = .noRoute
        case EPERM, EACCES: self = .notPermitted
        default: self = .failed(String(cString: strerror(code)))
        }
    }
}
