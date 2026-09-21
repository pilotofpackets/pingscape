import Darwin
import Foundation

/// A BSD socket with waits that end at a deadline or when a `CancelFlag` is set.
///
/// Blocking on purpose: it runs on a background thread (see `Blocking`). Each
/// wait is a short `poll`, so a stop is noticed within about 100 ms.
final class POSIXSocket {
    let fd: Int32

    init(family: Int32, type: Int32, proto: Int32 = 0) throws {
        fd = socket(family, type, proto)
        guard fd >= 0 else { throw ToolError(errno: errno) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    deinit { close(fd) }

    /// Waits until the socket is ready for `events`. Throws `.timeout` at the
    /// deadline and `CancellationError` when cancelled.
    func wait(for events: Int16, deadline: Deadline, cancel: CancelFlag) throws {
        while true {
            if cancel.isCancelled { throw CancellationError() }
            let remaining = deadline.remainingMilliseconds
            if remaining == 0 { throw ToolError.timeout }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(remaining, 100)))
            if ready > 0 { return }
            if ready < 0, errno != EINTR { throw ToolError(errno: errno) }
        }
    }

    /// Connects, waiting at most until the deadline.
    func connect(to address: ResolvedAddress, port: UInt16, deadline: Deadline, cancel: CancelFlag) throws {
        let status = address.withSockaddr(port: port) { sa, length in Darwin.connect(fd, sa, length) }
        if status == 0 { return }
        guard errno == EINPROGRESS else { throw ToolError(errno: errno) }
        try wait(for: Int16(POLLOUT), deadline: deadline, cancel: cancel)
        try throwPendingError()
    }

    /// Reads and clears the error of a finished non-blocking connect.
    func throwPendingError() throws {
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
        if error != 0 { throw ToolError(errno: error) }
    }

    /// Sends everything, waiting while the send buffer is full.
    func sendAll(_ bytes: [UInt8], deadline: Deadline, cancel: CancelFlag) throws {
        var sent = 0
        while sent < bytes.count {
            let count = bytes.withUnsafeBytes { raw in
                Darwin.send(fd, raw.baseAddress! + sent, bytes.count - sent, 0)
            }
            if count > 0 {
                sent += count
            } else if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                try wait(for: Int16(POLLOUT), deadline: deadline, cancel: cancel)
            } else if count < 0, errno == EINTR {
                continue
            } else {
                throw ToolError(errno: count < 0 ? errno : EPIPE)
            }
        }
    }

    /// Reads what arrives next (at most `limit` bytes). An empty result means
    /// the peer closed the connection.
    func receive(limit: Int, deadline: Deadline, cancel: CancelFlag) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: limit)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress, limit, 0) }
            if count >= 0 { return Array(buffer.prefix(count)) }
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                try wait(for: Int16(POLLIN), deadline: deadline, cancel: cancel)
            } else {
                throw ToolError(errno: errno)
            }
        }
    }

    /// Reads exactly `count` bytes, or throws if the peer closes early.
    func receiveExactly(_ count: Int, deadline: Deadline, cancel: CancelFlag) throws -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(count)
        while result.count < count {
            let chunk = try receive(limit: count - result.count, deadline: deadline, cancel: cancel)
            if chunk.isEmpty { throw ToolError.failed("Connection closed") }
            result += chunk
        }
        return result
    }

    /// One datagram and the address it came from.
    func receiveFrom(limit: Int) -> (bytes: [UInt8], from: [UInt8])? {
        var buffer = [UInt8](repeating: 0, count: limit)
        var from = sockaddr_storage()
        var fromLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let count = withUnsafeMutablePointer(to: &from) { fromPointer in
            fromPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                buffer.withUnsafeMutableBytes {
                    Darwin.recvfrom(fd, $0.baseAddress, limit, 0, sa, &fromLength)
                }
            }
        }
        guard count > 0 else { return nil }
        let fromBytes = withUnsafeBytes(of: &from) { Array($0.prefix(Int(fromLength))) }
        return (Array(buffer.prefix(count)), fromBytes)
    }

    func setTimeToLive(_ hops: Int32, ipv6: Bool) {
        var value = hops
        if ipv6 {
            setsockopt(fd, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &value, socklen_t(MemoryLayout<Int32>.size))
        } else {
            setsockopt(fd, IPPROTO_IP, IP_TTL, &value, socklen_t(MemoryLayout<Int32>.size))
        }
    }
}

extension ResolvedAddress {
    /// The numeric text of a raw `sockaddr` (as `recvfrom` fills it).
    static func text(ofSockaddr bytes: [UInt8]) -> String? {
        guard bytes.count >= MemoryLayout<sockaddr>.size else { return nil }
        return bytes.withUnsafeBytes { raw in
            SocketAddress.numericHost(raw.baseAddress!.assumingMemoryBound(to: sockaddr.self))
        }
    }
}
