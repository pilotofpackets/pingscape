import Foundation

/// Throughput between two counter readings.
public struct RateSample: Sendable, Equatable {
    public let time: Date
    public let receivedBytesPerSecond: Double
    public let sentBytesPerSecond: Double
}

/// Turns the ever-growing interface counters into a rate.
///
/// A counter that goes backwards (interface reset, wrap-around) gives no
/// sample: the point is dropped and the next one starts fresh, so there is no
/// spike.
public struct RateSampler: Sendable {
    private var previous: (time: Date, received: UInt64, sent: UInt64)?

    public init() {}

    public mutating func sample(received: UInt64, sent: UInt64, at time: Date) -> RateSample? {
        defer { previous = (time, received, sent) }
        guard let previous else { return nil }
        let seconds = time.timeIntervalSince(previous.time)
        guard seconds > 0, received >= previous.received, sent >= previous.sent else { return nil }
        return RateSample(
            time: time,
            receivedBytesPerSecond: Double(received - previous.received) / seconds,
            sentBytesPerSecond: Double(sent - previous.sent) / seconds)
    }

    /// Forget the last reading, for example after switching the interface.
    public mutating func reset() { previous = nil }
}

/// The latest round trips, for loss and jitter over a window.
public struct LatencyWindow: Sendable, Equatable {
    /// 60 pings: a minute at one ping per second.
    public static let defaultSize = 60

    private let size: Int
    /// `nil` is a ping that got no answer.
    private var results: [Double?] = []

    public init(size: Int = LatencyWindow.defaultSize) {
        self.size = size
    }

    public mutating func record(milliseconds: Double?) {
        results.append(milliseconds)
        if results.count > size { results.removeFirst(results.count - size) }
    }

    public var count: Int { results.count }

    /// The most recent answered round trip.
    public var latest: Double? { results.last ?? nil }

    public var lostPercent: Double? {
        results.isEmpty ? nil : Double(results.filter { $0 == nil }.count) / Double(results.count) * 100
    }

    /// The mean of the absolute differences of consecutive answered round
    /// trips, the same definition as in the Ping tool.
    public var jitter: Double? {
        let answered = results.compactMap { $0 }
        guard answered.count > 1 else { return nil }
        let differences = zip(answered, answered.dropFirst()).map { abs($1 - $0) }
        return differences.reduce(0, +) / Double(differences.count)
    }
}
