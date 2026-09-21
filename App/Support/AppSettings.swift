import Foundation
import Observation

/// How throughput is shown in the Live tab and in reports.
enum RateUnit: String, CaseIterable, Identifiable {
    case megabitPerSecond
    case megabytePerSecond

    var id: String { rawValue }

    /// "12.4 Mbit/s", or "820 kbit/s" below one megabit.
    func string(bytesPerSecond: Double) -> String {
        let (value, large, small) =
            switch self {
            case .megabitPerSecond: (bytesPerSecond * 8, "Mbit/s", "kbit/s")
            case .megabytePerSecond: (bytesPerSecond, "MB/s", "kB/s")
            }
        if value < 1_000_000 {
            return "\((value / 1_000).formatted(.number.precision(.fractionLength(0)))) \(small)"
        }
        let megas = value / 1_000_000
        let digits = megas < 10 ? 2 : 1
        return "\(megas.formatted(.number.precision(.fractionLength(digits)))) \(large)"
    }
}

/// The few settings the app keeps, in `UserDefaults` without iCloud.
@MainActor
@Observable
final class AppSettings {
    nonisolated static let externalLookupsKey = "externalLookups"
    nonisolated static let externalPromptShownKey = "externalPromptShown"
    nonisolated static let rateUnitKey = "rateUnit"

    private let defaults = UserDefaults.standard

    /// Public IP address, reverse DNS and provider. Off until the user agrees.
    var externalLookups: Bool {
        didSet { defaults.set(externalLookups, forKey: Self.externalLookupsKey) }
    }

    /// The one-time question on first launch has been answered.
    var externalPromptShown: Bool {
        didSet { defaults.set(externalPromptShown, forKey: Self.externalPromptShownKey) }
    }

    var rateUnit: RateUnit {
        didSet { defaults.set(rateUnit.rawValue, forKey: Self.rateUnitKey) }
    }

    init() {
        externalLookups = defaults.bool(forKey: Self.externalLookupsKey)
        externalPromptShown = defaults.bool(forKey: Self.externalPromptShownKey)
        rateUnit = RateUnit(rawValue: defaults.string(forKey: Self.rateUnitKey) ?? "") ?? .megabitPerSecond
    }
}
