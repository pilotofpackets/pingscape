import Foundation
import Testing

@testable import Pingscape

@Suite("New Year greeting")
struct NewYearGreetingTests {
    private static let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func calendar(_ identifier: Calendar.Identifier, _ timeZone: TimeZone = berlin) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar(.gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// "2027-01-01 00:00 2027" for each New Year.
    private func summary(_ identifier: Calendar.Identifier, after now: Date, language: String = "en") -> [String] {
        NewYearGreeting.upcoming(after: now, calendar: calendar(identifier), language: language).map {
            let c = $0.components
            return String(format: "%04d-%02d-%02d %02d:%02d ", c.year!, c.month!, c.day!, c.hour!, c.minute!) + $0.year
        }
    }

    @Test("Gregorian: midnight on 1 January, also on New Year's Eve and New Year's Day")
    func gregorian() {
        let expected = ["2027-01-01 00:00 2027", "2028-01-01 00:00 2028", "2029-01-01 00:00 2029"]
        #expect(summary(.gregorian, after: date(2026, 11, 18)) == expected)
        #expect(summary(.gregorian, after: date(2026, 12, 31, 23, 59)) == expected)
        #expect(summary(.gregorian, after: date(2027, 1, 1, 0, 1)).first == "2028-01-01 00:00 2028")
        #expect(summary(.iso8601, after: date(2026, 11, 18)) == expected)
    }

    @Test("Other calendars: their own New Year's Day and their own year", arguments: [
        (Calendar.Identifier.buddhist, "2027-01-01 00:00 2570"),
        (.japanese, "2027-01-01 00:00 Reiwa 9"),
        (.republicOfChina, "2027-01-01 00:00 Minguo 116"),
        (.chinese, "2027-02-06 00:00 2027"),
        (.hebrew, "2027-10-02 00:00 5788"),
        (.islamicUmmAlQura, "2027-06-06 00:00 1449"),
        (.persian, "2027-03-21 00:00 1406"),
        (.indian, "2027-03-22 00:00 1949"),
        (.ethiopicAmeteMihret, "2027-09-12 00:00 2020"),
    ])
    func otherCalendars(_ identifier: Calendar.Identifier, first: String) {
        let newYears = summary(identifier, after: date(2026, 11, 18))
        #expect(newYears.count == NewYearGreeting.yearsAhead)
        #expect(newYears.first == first)
    }

    @Test("Each New Year follows the one before")
    func consecutive() {
        for identifier in [Calendar.Identifier.gregorian, .hebrew, .islamicUmmAlQura, .chinese, .persian] {
            let dates = NewYearGreeting.upcoming(after: date(2026, 11, 18), calendar: calendar(identifier))
                .map { calendar(.gregorian).date(from: $0.components)! }
            #expect(dates == dates.sorted() && Set(dates).count == dates.count, "\(identifier)")
        }
    }

    @Test("Local time, not a fixed instant: the trigger carries no time zone")
    func floating() {
        let tokyo = NewYearGreeting.upcoming(after: date(2026, 11, 18), calendar: calendar(.gregorian, TimeZone(identifier: "Asia/Tokyo")!))
        let berlin = NewYearGreeting.upcoming(after: date(2026, 11, 18), calendar: calendar(.gregorian))
        #expect(tokyo == berlin)
        let trigger = NewYearGreeting.trigger(for: berlin[0])
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.timeZone == nil)
    }

    @Test("Fires at the next local midnight of 1 January")
    func nextTriggerDate() {
        let newYear = NewYearGreeting.upcoming(after: .now, calendar: Calendar(identifier: .gregorian))[0]
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let year = local.component(.year, from: .now) + 1
        #expect(NewYearGreeting.trigger(for: newYear).nextTriggerDate() == local.date(from: DateComponents(year: year, month: 1, day: 1)))
    }

    @Test("Era names in the language of the text")
    func eraLanguage() {
        #expect(summary(.republicOfChina, after: date(2026, 11, 18), language: "fr").first == "2027-01-01 00:00 RdC 116")
    }

    @Test("The title carries the year without a thousands separator, the identifier its date")
    func content() {
        let newYear = NewYearGreeting.upcoming(after: date(2026, 11, 18), calendar: calendar(.gregorian))[0]
        #expect(NewYearGreeting.content(for: newYear).title.contains("2027"))
        #expect(NewYearGreeting.identifier(for: newYear) == "newYear.2027-1-1")
    }
}
