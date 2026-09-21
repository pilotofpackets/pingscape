import Foundation
import Synchronization

/// Set from outside to stop blocking work. The work checks it between short
/// waits, so a stop takes effect within about a tenth of a second.
public final class CancelFlag: Sendable {
    private let flag = Atomic<Bool>(false)

    public init() {}

    public var isCancelled: Bool { flag.load(ordering: .relaxed) }

    public func cancel() { flag.store(true, ordering: .relaxed) }
}

/// Runs blocking system calls (sockets, `getaddrinfo`) off the cooperative
/// thread pool, so waiting on them never stalls the interface.
///
/// Cancelling the calling task returns at once with `CancellationError`. The
/// work sees the flag and stops at its next check. A call that cannot be
/// interrupted (a slow name lookup) finishes in the background and its result
/// is dropped.
enum Blocking {
    private final class State<T: Sendable>: Sendable {
        struct Inner {
            var continuation: CheckedContinuation<T, any Error>?
            var cancelled = false
            var finished = false
        }

        let flag = CancelFlag()
        private let inner = Mutex(Inner())

        func install(_ continuation: CheckedContinuation<T, any Error>) {
            let cancelled = inner.withLock { inner -> Bool in
                if inner.cancelled { return true }
                inner.continuation = continuation
                return false
            }
            if cancelled { continuation.resume(throwing: CancellationError()) }
        }

        func finish(_ result: Result<T, any Error>) {
            let continuation = inner.withLock { inner -> CheckedContinuation<T, any Error>? in
                inner.finished = true
                defer { inner.continuation = nil }
                return inner.continuation
            }
            continuation?.resume(with: result)
        }

        func cancel() {
            flag.cancel()
            let continuation = inner.withLock { inner -> CheckedContinuation<T, any Error>? in
                inner.cancelled = true
                defer { inner.continuation = nil }
                return inner.continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    static func run<T: Sendable>(
        qos: DispatchQoS.QoSClass = .userInitiated,
        _ work: @escaping @Sendable (CancelFlag) throws -> T
    ) async throws -> T {
        let state = State<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                DispatchQueue.global(qos: qos).async {
                    state.finish(Result { try work(state.flag) })
                }
            }
        } onCancel: {
            state.cancel()
        }
    }
}

/// A point in time to wait until, on a clock that does not jump.
struct Deadline: Sendable {
    private let end: UInt64

    init(afterMilliseconds milliseconds: Int) {
        end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + UInt64(max(milliseconds, 0)) * 1_000_000
    }

    var remainingMilliseconds: Int {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        return now >= end ? 0 : Int((end - now + 999_999) / 1_000_000)
    }

    var isExpired: Bool { remainingMilliseconds == 0 }
}

/// Milliseconds on the same monotonic clock, for timing round trips.
func monotonicMilliseconds() -> Double {
    Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000
}
