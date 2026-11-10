import Darwin
import Foundation

/// A STUN server: a host name or address and its UDP port.
public struct STUNServer: Sendable, Hashable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16 = 3478) {
        self.host = host
        self.port = port
    }

    /// Two operators, and two addresses of one of them, so a mapping that
    /// changes with the destination shows even when one server is down.
    public static let defaults: [STUNServer] = [
        STUNServer(host: "stun.cloudflare.com", port: 3478),
        STUNServer(host: "stun.l.google.com", port: 19302),
        STUNServer(host: "stun1.l.google.com", port: 19302),
    ]

    public var text: String { "\(host):\(port)" }
}

/// What one STUN server saw.
public struct STUNMapping: Sendable, Equatable, Identifiable {
    public let server: STUNServer
    /// The address the server was reached at.
    public let serverAddress: String?
    /// The address and port the request arrived from, as the server saw it.
    public let publicAddress: String?
    public let publicPort: UInt16?
    public let milliseconds: Double?
    public let error: ToolError?

    public var id: STUNServer { server }

    public init(
        server: STUNServer, serverAddress: String?, publicAddress: String?, publicPort: UInt16?,
        milliseconds: Double?, error: ToolError?
    ) {
        self.server = server
        self.serverAddress = serverAddress
        self.publicAddress = publicAddress
        self.publicPort = publicPort
        self.milliseconds = milliseconds
        self.error = error
    }

    var endpoint: String? {
        guard let publicAddress, let publicPort else { return nil }
        return "\(publicAddress):\(publicPort)"
    }
}

/// A run: one local socket, one request to each server.
public struct STUNReport: Sendable, Equatable {
    public let localAddress: String?
    public let localPort: UInt16?
    public let mappings: [STUNMapping]

    public init(localAddress: String?, localPort: UInt16?, mappings: [STUNMapping]) {
        self.localAddress = localAddress
        self.localPort = localPort
        self.mappings = mappings
    }

    private var answered: [STUNMapping] { mappings.filter { $0.endpoint != nil } }

    /// Whether the address the servers saw differs from the device's own.
    /// `nil` before an answer.
    public var isTranslated: Bool? {
        guard let localAddress, let first = answered.first?.publicAddress else { return nil }
        return first != localAddress
    }

    /// Whether the public port is the local one.
    public var keepsPort: Bool? {
        guard let localPort, let first = answered.first?.publicPort else { return nil }
        return first == localPort
    }

    /// Whether all servers saw the same address and port (RFC 4787:
    /// endpoint-independent mapping). Only from servers at different
    /// addresses, and only with at least two answers.
    public var sameMappingForAllServers: Bool? {
        var byServerAddress: [String: String] = [:]
        for mapping in answered {
            guard let address = mapping.serverAddress, let endpoint = mapping.endpoint else { continue }
            byServerAddress[address] = endpoint
        }
        guard byServerAddress.count >= 2 else { return nil }
        return Set(byServerAddress.values).count == 1
    }
}

/// STUN binding requests (RFC 5389).
enum STUNMessage {
    static let magicCookie: UInt32 = 0x2112_A442

    static func bindingRequest(transactionID: [UInt8]) -> [UInt8] {
        precondition(transactionID.count == 12)
        return [0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42] + transactionID
    }

    /// The mapped address of a binding success response to `transactionID`.
    /// XOR-MAPPED-ADDRESS first, MAPPED-ADDRESS from older servers otherwise.
    static func mappedAddress(in data: [UInt8], transactionID: [UInt8]) -> (address: String, port: UInt16)? {
        guard data.count >= 20, data[0] == 0x01, data[1] == 0x01,
            Array(data[4..<8]) == [0x21, 0x12, 0xA4, 0x42], Array(data[8..<20]) == transactionID
        else { return nil }
        let length = Int(data[2]) << 8 | Int(data[3])
        let end = min(data.count, 20 + length)
        var plain: (String, UInt16)?
        var offset = 20
        while offset + 4 <= end {
            let type = Int(data[offset]) << 8 | Int(data[offset + 1])
            let size = Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            let value = offset + 4
            guard value + size <= end else { break }
            let attribute = Array(data[value..<(value + size)])
            if type == 0x0020, let found = address(attribute, xor: Array(data[4..<20])) { return found }
            if type == 0x0001, plain == nil { plain = address(attribute, xor: nil) }
            // Attributes are padded to four bytes.
            offset = value + (size + 3) / 4 * 4
        }
        return plain
    }

    /// An address attribute: reserved, family, port, address. With `xor` the
    /// port is XORed with the cookie's top half and the address with the
    /// cookie (IPv4) or cookie and transaction ID (IPv6).
    private static func address(_ value: [UInt8], xor: [UInt8]?) -> (String, UInt16)? {
        guard value.count >= 8 else { return nil }
        let family = value[1]
        var port = UInt16(value[2]) << 8 | UInt16(value[3])
        var bytes = Array(value[4...])
        if let xor {
            port ^= 0x2112
            for index in bytes.indices where index < xor.count { bytes[index] ^= xor[index] }
        }
        switch (family, bytes.count) {
        case (1, 4):
            return (bytes.map(String.init).joined(separator: "."), port)
        case (2, 16):
            var address = in6_addr()
            withUnsafeMutableBytes(of: &address) { $0.copyBytes(from: bytes) }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            return (String(nulTerminated: buffer), port)
        default:
            return nil
        }
    }
}

public enum STUNTool {
    /// Asks every server from one socket, over IPv4 or IPv6. A server without
    /// an address of that family gets an error row.
    public static func run(
        servers: [STUNServer] = STUNServer.defaults, ipv6: Bool, timeoutMilliseconds: Int = 3000
    ) async throws -> STUNReport {
        var targets: [(STUNServer, Result<ResolvedAddress, ToolError>)] = []
        for server in servers {
            let addresses = (try? await HostResolver.resolve(server.host)) ?? []
            // A name with addresses, none of them of this family: the system
            // leaves out a family it has no route for.
            if let address = addresses.first(where: { $0.isIPv6 == ipv6 }) {
                targets.append((server, .success(address)))
            } else {
                targets.append((server, .failure(addresses.isEmpty ? .cannotResolve : .noRoute)))
            }
        }
        try Task.checkCancellation()
        let resolved = targets
        return try await Blocking.run { cancel in
            try exchange(resolved, ipv6: ipv6, timeout: timeoutMilliseconds, cancel: cancel)
        }
    }

    private static func exchange(
        _ targets: [(STUNServer, Result<ResolvedAddress, ToolError>)], ipv6: Bool, timeout: Int, cancel: CancelFlag
    ) throws -> STUNReport {
        let socket = try POSIXSocket(family: ipv6 ? AF_INET6 : AF_INET, type: SOCK_DGRAM)
        let deadline = Deadline(afterMilliseconds: timeout)
        struct Pending {
            let index: Int
            let address: ResolvedAddress
            let port: UInt16
            let request: [UInt8]
            var sentAt: Double
        }
        var pending: [[UInt8]: Pending] = [:]
        var results: [Int: STUNMapping] = [:]

        for (index, (server, resolution)) in targets.enumerated() {
            let address: ResolvedAddress
            switch resolution {
            case .success(let found): address = found
            case .failure(let error):
                results[index] = STUNMapping(
                    server: server, serverAddress: nil, publicAddress: nil, publicPort: nil, milliseconds: nil,
                    error: error)
                continue
            }
            let transaction = (0..<12).map { _ in UInt8.random(in: 0...255) }
            pending[transaction] = Pending(
                index: index, address: address, port: server.port,
                request: STUNMessage.bindingRequest(transactionID: transaction), sentAt: 0)
        }

        func send(_ item: inout Pending) {
            let request = item.request
            _ = request.withUnsafeBytes { raw in
                item.address.withSockaddr(port: item.port) { sa, length in
                    Darwin.sendto(socket.fd, raw.baseAddress, request.count, 0, sa, length)
                }
            }
            item.sentAt = monotonicMilliseconds()
        }
        for key in pending.keys { send(&pending[key]!) }
        // The system picks the local port at the first send.
        let localPort = socket.localPort()
        let localAddress = targets.compactMap { try? $0.1.get() }.first.flatMap(OutgoingInterface.localAddress(for:))

        // UDP may lose a request: resend every 500 ms until the deadline.
        var lastSend = monotonicMilliseconds()
        while !pending.isEmpty {
            if cancel.isCancelled { throw CancellationError() }
            if deadline.remainingMilliseconds == 0 { break }
            var descriptor = pollfd(fd: socket.fd, events: Int16(POLLIN), revents: 0)
            _ = poll(&descriptor, 1, Int32(min(deadline.remainingMilliseconds, 100)))
            while let (bytes, _) = socket.receiveFrom(limit: 1500) {
                guard bytes.count >= 20 else { continue }
                let transaction = Array(bytes[8..<20])
                guard let item = pending[transaction] else { continue }
                let (server, _) = targets[item.index]
                let mapped = STUNMessage.mappedAddress(in: bytes, transactionID: transaction)
                results[item.index] = STUNMapping(
                    server: server, serverAddress: item.address.text, publicAddress: mapped?.address,
                    publicPort: mapped?.port, milliseconds: monotonicMilliseconds() - item.sentAt,
                    error: mapped == nil ? .unreadable : nil)
                pending[transaction] = nil
            }
            if monotonicMilliseconds() - lastSend >= 500 {
                for key in pending.keys { send(&pending[key]!) }
                lastSend = monotonicMilliseconds()
            }
        }
        for item in pending.values {
            results[item.index] = STUNMapping(
                server: targets[item.index].0, serverAddress: item.address.text, publicAddress: nil, publicPort: nil,
                milliseconds: nil, error: .timeout)
        }
        return STUNReport(
            localAddress: localAddress, localPort: localPort,
            mappings: targets.indices.compactMap { results[$0] })
    }
}

extension POSIXSocket {
    /// The local port, once the system has picked one.
    func localPort() -> UInt16? {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let status = withUnsafeMutablePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard status == 0 else { return nil }
        let port: UInt16 = withUnsafeBytes(of: &storage) { raw in
            // sin_port and sin6_port sit at the same offset, in network order.
            UInt16(raw[2]) << 8 | UInt16(raw[3])
        }
        return port == 0 ? nil : port
    }
}
