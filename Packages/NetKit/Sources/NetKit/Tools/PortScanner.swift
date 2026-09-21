import Foundation

public enum PortState: Sendable, Equatable {
    /// The handshake completed.
    case open
    /// The target answered and refused.
    case closed
    /// Nothing came back in the time limit. The app does not say "filtered":
    /// that would be an interpretation.
    case noResponse
}

public enum PortScanEvent: Sendable, Equatable {
    case started(address: String)
    case result(port: Int, state: PortState, milliseconds: Double?)
    case progress(done: Int, total: Int)
    /// Every probe failed for the same system reason, for example no route.
    case failed(ToolError)
    case finished
}

/// The ports the app scans by default, as in the reference app.
public enum PortScanner {
    public static let commonPorts: [Int] = [
        20, 21, 22, 23, 25, 53, 67, 69, 80, 110, 123, 135, 137, 139, 143, 161,
        389, 443, 445, 465, 514, 515, 548, 587, 631, 636, 993, 995, 1080, 1194,
        1433, 1521, 1723, 1883, 2049, 2082, 2083, 3000, 3128, 3306, 3389, 4444,
        5000, 5060, 5222, 5432, 5900, 5985, 6379, 7000, 8000, 8006, 8008, 8080,
        8081, 8123, 8443, 8883, 9000, 9090, 9100, 9200, 10000, 27017, 32400,
        51820, 62078,
    ]

    /// The connection time limit and the number of attempts at a time.
    public static let timeoutMilliseconds = 900
    public static let concurrency = 32

    public static func run(
        address: ResolvedAddress, ports: [Int], timeoutMilliseconds: Int = timeoutMilliseconds,
        concurrency: Int = concurrency
    ) -> AsyncStream<PortScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(.started(address: address.text))
                let targets = ports.enumerated().compactMap { index, port -> TCPProbe.Target? in
                    guard (1...65535).contains(port) else { return nil }
                    return TCPProbe.Target(id: index, address: address, port: UInt16(port))
                }
                let total = targets.count
                do {
                    let failures = try await Blocking.run { cancel -> [ToolError] in
                        var done = 0
                        var failures: [ToolError] = []
                        var answered = false
                        TCPProbe.run(
                            targets: targets, timeoutMilliseconds: timeoutMilliseconds,
                            concurrency: concurrency, cancel: cancel
                        ) { id, result in
                            let port = ports[id]
                            done += 1
                            switch result {
                            case .open(let ms):
                                answered = true
                                continuation.yield(.result(port: port, state: .open, milliseconds: ms))
                            case .closed(let ms):
                                answered = true
                                continuation.yield(.result(port: port, state: .closed, milliseconds: ms))
                            case .noResponse:
                                continuation.yield(.result(port: port, state: .noResponse, milliseconds: nil))
                            case .failed(let error):
                                failures.append(error)
                                continuation.yield(.result(port: port, state: .noResponse, milliseconds: nil))
                            }
                            continuation.yield(.progress(done: done, total: total))
                        }
                        return answered ? [] : failures
                    }
                    if let first = failures.first, failures.allSatisfy({ $0 == first }) {
                        continuation.yield(.failed(first))
                    }
                    continuation.yield(.finished)
                } catch {
                    // Cancelled: what is on screen stays.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// What a port is usually used for. Only ports with a fixed assignment
/// (IANA) are listed. The app shows it as "usually SSH", never as a claim about
/// the service that answers. Ports that are merely popular for one product
/// (3000, 4444, 8123 …) are left out, because that would be a guess.
public enum PortNames {
    private static let names: [Int: String] = [
        20: "FTP data", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP", 53: "DNS", 67: "DHCP",
        69: "TFTP", 80: "HTTP", 110: "POP3", 123: "NTP", 135: "MS RPC", 137: "NetBIOS name",
        139: "NetBIOS session", 143: "IMAP", 161: "SNMP", 389: "LDAP", 443: "HTTPS", 445: "SMB",
        465: "SMTPS", 515: "LPD printing", 548: "AFP", 587: "SMTP submission", 631: "IPP",
        636: "LDAPS", 993: "IMAPS", 995: "POP3S", 1080: "SOCKS", 1194: "OpenVPN", 1433: "SQL Server",
        1723: "PPTP", 1883: "MQTT", 2049: "NFS", 3306: "MySQL", 3389: "RDP", 5060: "SIP",
        5222: "XMPP", 5432: "PostgreSQL", 5900: "VNC", 5985: "WinRM", 8080: "HTTP alternate",
        8883: "MQTT over TLS", 9100: "Raw printing",
    ]

    public static func name(for port: Int) -> String? { names[port] }
}
