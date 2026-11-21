//
//  ReminderDateTests.swift
//  boringNotchTests
//

import Foundation
import Testing

/// Reminders are due on a day, sometimes at a time. The day must be the user's day,
/// wherever they are, and a timed reminder keeps the zone it was set in.
@Suite("Reminder due dates")
struct ReminderDateTests {

    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    @Test("An all-day reminder is local midnight of its day, in any time zone",
          arguments: ["America/Los_Angeles", "Asia/Kolkata", "Asia/Tokyo", "Pacific/Kiritimati"])
    func allDayIsLocalDay(zone: String) throws {
        let components = DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 4, day: 20)
        let calendar = try calendar(zone)
        let date = try #require(components.reminderDate(in: calendar, fallbackTimeZone: TimeZone(secondsFromGMT: 0)))
        #expect(calendar.dateComponents([.year, .month, .day, .hour], from: date)
                == DateComponents(year: 2026, month: 4, day: 20, hour: 0))
        #expect(components.isAllDayReminder)
    }

    @Test("Days that gain or lose an hour still start at their own midnight")
    func daylightSavingDays() throws {
        let calendar = try calendar("America/Edmonton")
        for (month, day, hours) in [(3, 10, 23), (11, 3, 25)] {
            let date = try #require(DateComponents(year: 2024, month: month, day: day)
                .reminderDate(in: calendar, fallbackTimeZone: nil))
            let interval = try #require(calendar.dateInterval(of: .day, for: date))
            #expect(date == interval.start)
            #expect(interval.duration == Double(hours * 3600))
        }
    }

    @Test("A timed reminder keeps its own time zone")
    func timedKeepsZone() throws {
        let calendar = try calendar("America/Los_Angeles")
        let components = DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 4, day: 20, hour: 0, minute: 30)
        let date = try #require(components.reminderDate(in: calendar, fallbackTimeZone: TimeZone(identifier: "Asia/Tokyo")))
        #expect(calendar.dateComponents([.day, .hour, .minute], from: date) == DateComponents(day: 19, hour: 17, minute: 30))
        #expect(!components.isAllDayReminder)
    }

    @Test("The reminder's zone is used only when the components have none")
    func fallbackZoneOnlyWhenMissing() throws {
        let calendar = try calendar("America/Los_Angeles")
        let components = DateComponents(year: 2026, month: 4, day: 20, hour: 0, minute: 30)
        let utc = try #require(components.reminderDate(in: calendar, fallbackTimeZone: TimeZone(secondsFromGMT: 0)))
        let local = try #require(components.reminderDate(in: calendar, fallbackTimeZone: nil))
        #expect(local.timeIntervalSince(utc) == 7 * 3600)
    }

    @Test("A non-Gregorian system calendar still reads the Gregorian due day")
    func nonGregorianSystemCalendar() throws {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Bangkok"))
        let date = try #require(DateComponents(year: 2026, month: 4, day: 20)
            .reminderDate(in: calendar, fallbackTimeZone: nil))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        #expect(gregorian.component(.year, from: date) == 2026)
        #expect(gregorian.component(.day, from: date) == 20)
    }

    @Test("A time of midnight is a timed reminder, not an all-day one")
    func explicitMidnightIsTimed() {
        #expect(!DateComponents(year: 2026, month: 4, day: 20, hour: 0).isAllDayReminder)
        #expect(!DateComponents(year: 2026, month: 4, day: 20, minute: 0).isAllDayReminder)
    }
}
