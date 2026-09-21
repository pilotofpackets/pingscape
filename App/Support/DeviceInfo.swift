import Foundation
import UIKit

/// The device and app, for the header of a report and for the diagnostic dump.
@MainActor
enum DeviceInfo {
    /// `iPhone17,3`. In the simulator the identifier of the simulated model.
    static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// "iPhone 16" where the identifier is known, otherwise the identifier itself.
    static var modelName: String {
        let names: [String: String] = [
            "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max",
            "iPhone11,8": "iPhone XR", "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2nd generation)",
            "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max", "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,6": "iPhone SE (3rd generation)",
            "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,5": "iPhone 16e",
        ]
        return names[modelIdentifier] ?? modelIdentifier
    }

    static var systemVersion: String { UIDevice.current.systemVersion }

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var appBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }

    /// 2026-09-21 14:05:12+02:00: ISO 8601 in the time zone of the device.
    private static let timestamp = Date.ISO8601FormatStyle(
        dateSeparator: .dash, dateTimeSeparator: .space, timeSeparator: .colon, timeZoneSeparator: .colon,
        includingFractionalSeconds: false, timeZone: .current)

    /// The two header lines of a report.
    static func reportHeader(at date: Date = Date()) -> [String] {
        [
            "Pingscape \(appVersion) (\(appBuild)) · \(date.formatted(timestamp))",
            "\(modelName) · iOS \(systemVersion)",
        ]
    }
}
