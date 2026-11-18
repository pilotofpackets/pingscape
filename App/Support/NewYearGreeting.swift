import Foundation
import UserNotifications

/// A greeting at midnight on New Year's Day: "Happy New Year 2027!"
///
/// New Year is the first day of the year in the calendar set on the device, at
/// local midnight: 1 January in the Gregorian, Buddhist or Japanese calendar,
/// Rosh Hashanah in the Hebrew one, 1 Muharram in the Islamic ones, Nowruz in
/// the Persian one, the Lunar New Year in the Chinese one. The year is written
/// the way that calendar counts it.
///
/// Uses provisional permission: iOS shows no dialog and delivers quietly to
/// Notification Center (no banner, no sound). The first greeting there offers
/// to keep or turn off notifications from Pingscape.
///
/// A repeating trigger would repeat the text with its year as well, so every
/// launch schedules the next few New Years one by one, each with its own year,
/// in the calendar and language the device has then. Someone who skips the app
/// for a year still gets the next greeting.
///
/// Never in demo mode (screenshots, UI tests) and never inside an app that
/// embeds Pingscape: there the host owns the notifications.
@MainActor
enum NewYearGreeting {
    nonisolated static let identifierPrefix = "newYear."
    nonisolated static let yearsAhead = 3

    struct NewYear: Equatable {
        /// Gregorian date and time of local midnight, without a time zone: the
        /// trigger fires at that wall-clock time wherever the device is then.
        let components: DateComponents
        /// "2027", "5788", "Reiwa 9".
        let year: String
    }

    /// The next `count` New Years after `now` in `calendar`.
    nonisolated static func upcoming(
        after now: Date, calendar: Calendar = .current, language: String = appLanguage, count: Int = yearsAhead
    ) -> [NewYear] {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        var result: [NewYear] = []
        var date = now
        for _ in 0..<count {
            guard let start = calendar.dateInterval(of: .year, for: date)?.end else { break }
            // Midnight, or the first hour that exists when a clock change skips it.
            var components = gregorian.dateComponents([.year, .month, .day, .hour, .minute], from: start)
            components.calendar = Calendar(identifier: .gregorian)
            result.append(NewYear(components: components, year: yearText(start, calendar: calendar, language: language)))
            date = start
        }
        return result
    }

    /// The language of the notification text, so era names match it.
    nonisolated static var appLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }

    nonisolated static func yearText(_ date: Date, calendar: Calendar, language: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: language)
        formatter.dateFormat =
            switch calendar.identifier {
            // The year counts from the start of an era: "Reiwa 9", "Minguo 116".
            case .japanese, .republicOfChina: "G y"
            // The year is a place in a 60-year cycle ("ding-wei"), meaningless in
            // these languages; the Lunar New Year is named by its Gregorian year.
            case .chinese: "r"
            default: "y"
            }
        return formatter.string(from: date)
    }

    nonisolated static func trigger(for newYear: NewYear) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: newYear.components, repeats: false)
    }

    /// In the language of the app at scheduling time; every launch schedules anew.
    nonisolated static func content(for newYear: NewYear) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Happy New Year \(newYear.year)!")
        content.body = String(localized: "The Pingscape team wishes you a great start to the new year.")
        content.sound = .default
        return content
    }

    nonisolated static func identifier(for newYear: NewYear) -> String {
        let date = newYear.components
        return identifierPrefix + [date.year, date.month, date.day].map { String($0 ?? 0) }.joined(separator: "-")
    }

    static func schedule(
        now: Date = .now,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        isDemo: Bool = DemoLaunch.isDemo
    ) async {
        guard !isDemo, bundleIdentifier == ReviewPrompt.bundleIdentifier else { return }
        let center = UNUserNotificationCenter.current()

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .provisional])
            status = await center.notificationSettings().authorizationStatus
        }

        let old = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard [.authorized, .provisional, .ephemeral].contains(status) else { return }

        for newYear in upcoming(after: now) {
            let request = UNNotificationRequest(
                identifier: identifier(for: newYear), content: content(for: newYear), trigger: trigger(for: newYear))
            try? await center.add(request)
        }
    }
}
