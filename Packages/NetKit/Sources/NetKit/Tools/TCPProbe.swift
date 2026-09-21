import Darwin
import Foundation

/// TCP connection attempts, many at a time on one thread.
///
/// Used by the port tool, the TCP fallback of Ping and the thorough LAN
/// search. Only the handshake happens: no data is sent.
enum TCPProbe {
    enum Result: Sendable, Equatable {
        /// The handshake completed.
        case open(milliseconds: Double)
        /// The target answered and refused.
        case closed(milliseconds: Double)
        /// Nothing came back in the time limit.
        case noResponse
        case failed(ToolError)
    }

    struct Target: Sendable {
        let id: Int
        let address: ResolvedAddress
        let port: UInt16
    }

    private struct Attempt {
        let socket: POSIXSocket
        let id: Int
        let started: Double
    }

    /// Tries every target, at most `concurrency` at a time, and reports each
    /// result as soon as it is known. Blocks until all are done or cancelled.
    static func run(
        targets: [Target], timeoutMilliseconds: Int, concurrency: Int, cancel: CancelFlag,
        onResult: (_ id: Int, _ result: Result) -> Void
    ) {
        var active: [Int32: Attempt] = [:]
        var next = 0

        func classify(_ error: ToolError, started: Double) -> Result {
            error == .refused ? .closed(milliseconds: monotonicMilliseconds() - started) : .failed(error)
        }

        while (next < targets.count || !active.isEmpty) && !cancel.isCancelled {
            while next < targets.count, active.count < max(concurrency, 1) {
                let target = targets[next]
                next += 1
                let started = monotonicMilliseconds()
                guard let socket = try? POSIXSocket(family: target.address.family, type: SOCK_STREAM) else {
                    onResult(target.id, .failed(.failed("No socket available")))
                    continue
                }
                let status = target.address.withSockaddr(port: target.port) { sa, length in
                    Darwin.connect(socket.fd, sa, length)
                }
                if status == 0 {
                    onResult(target.id, .open(milliseconds: monotonicMilliseconds() - started))
                } else if errno == EINPROGRESS {
                    active[socket.fd] = Attempt(socket: socket, id: target.id, started: started)
                } else {
                    onResult(target.id, classify(ToolError(errno: errno), started: started))
                }
            }
            guard !active.isEmpty else { continue }

            var descriptors = active.keys.map { pollfd(fd: $0, events: Int16(POLLOUT), revents: 0) }
            _ = poll(&descriptors, nfds_t(descriptors.count), 50)
            for descriptor in descriptors where descriptor.revents != 0 {
                guard let attempt = active.removeValue(forKey: descriptor.fd) else { continue }
                do {
                    try attempt.socket.throwPendingError()
                    onResult(attempt.id, .open(milliseconds: monotonicMilliseconds() - attempt.started))
                } catch let error as ToolError {
                    onResult(attempt.id, classify(error, started: attempt.started))
                } catch {
                    onResult(attempt.id, .failed(.failed("\(error)")))
                }
            }

            let now = monotonicMilliseconds()
            for (fd, attempt) in active where now - attempt.started >= Double(timeoutMilliseconds) {
                active[fd] = nil
                onResult(attempt.id, .noResponse)
            }
        }
    }

    /// One attempt, off the cooperative thread pool.
    static func once(
        address: ResolvedAddress, port: UInt16, timeoutMilliseconds: Int
    ) async throws -> Result {
        try await Blocking.run { cancel in
            var outcome: Result = .noResponse
            run(
                targets: [Target(id: 0, address: address, port: port)],
                timeoutMilliseconds: timeoutMilliseconds, concurrency: 1, cancel: cancel
            ) { _, result in outcome = result }
            return outcome
        }
    }
}
