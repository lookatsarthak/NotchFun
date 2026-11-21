//
//  ReminderDate.swift
//  NotchFun
//

import Foundation

/// Turning a reminder's due-date components into the moment the calendar should show it.
///
/// `DateComponents.date` is nil unless the components carry a calendar, and EventKit's
/// usually don't, so reminders were silently dropped. And a reminder due "on the 20th"
/// with no time means the 20th wherever the user is now, not midnight in whatever zone it
/// was written in: read in UTC from India it lands on the 19th or 21st.
///
/// From upstream boring.notch (3e8175d, 3cf9ee2).
extension DateComponents {
    /// A due date with no time of day: an all-day reminder.
    var isAllDayReminder: Bool {
        hour == nil && minute == nil && second == nil
    }

    /// The reminder's date in `calendar`.
    ///
    /// All-day: local midnight of that day, using the Gregorian calendar the components were
    /// written in even when the system calendar is not Gregorian. Timed: the components' own
    /// time zone, else `fallbackTimeZone` (the reminder's), else the calendar's.
    func reminderDate(in calendar: Calendar, fallbackTimeZone: TimeZone?) -> Date? {
        var reminderCalendar = calendar
        if isAllDayReminder {
            reminderCalendar = Calendar(identifier: .gregorian)
            reminderCalendar.timeZone = calendar.timeZone
        }

        var components = self
        components.calendar = reminderCalendar

        if isAllDayReminder {
            components.timeZone = reminderCalendar.timeZone
            components.hour = 0
            components.minute = 0
            components.second = 0
        } else if components.timeZone == nil {
            components.timeZone = fallbackTimeZone ?? reminderCalendar.timeZone
        }

        return reminderCalendar.date(from: components)
    }
}
