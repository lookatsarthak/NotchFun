//
//  MeetingReminder.swift
//  NotchFun
//

import AppKit
import Defaults
import EventKit
import Foundation

/// Shows "Standup in 2 min" in the closed notch shortly before a call starts.
///
/// One timer, set for the next call with a link and reset whenever something could have
/// moved it: the calendar changing, the Mac waking, the day rolling over, or the setting
/// being switched. Nothing polls. It only runs with the calendar shown and full calendar
/// access, and only for calls with a link, so a day of non-call events never fires.
@MainActor
@Observable
final class MeetingReminder {
    static let shared = MeetingReminder()

    /// How long before the start the heads-up appears.
    static let leadTime: TimeInterval = 2 * 60
    /// How long it stays.
    static let bannerDuration: TimeInterval = 10

    /// The call the banner is about while it shows.
    private(set) var current: EventModel?

    private var timer: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var settingsTask: Task<Void, Never>?
    /// So a reschedule within the lead time doesn't announce the same call twice.
    private var announcedIDs: Set<String> = []

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.EKEventStoreChanged, .NSCalendarDayChanged] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reschedule() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reschedule() }
        })
        settingsTask = Task { [weak self] in
            for await _ in Defaults.updates([.showCalendar, .showMeetingReminders, .calendarSelectionState]) {
                self?.reschedule()
            }
        }
    }

    private var isEnabled: Bool {
        Defaults[.showCalendar] && Defaults[.showMeetingReminders]
            && EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    private func reschedule() {
        timer?.cancel()
        timer = nil
        guard isEnabled else { return }
        timer = Task { [weak self] in
            guard let self else { return }
            let meetings = await CalendarManager.shared.upcomingMeetings()
            guard !Task.isCancelled,
                  let next = meetings.first(where: { !self.announcedIDs.contains(self.key($0)) })
            else { return }

            // Already inside the lead time (the Mac just woke, or NotchFun just started):
            // say it now rather than not at all.
            let wait = next.start.timeIntervalSinceNow - Self.leadTime
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
            }
            self.announce(next)
            // Back-to-back calls: line up the one after.
            self.reschedule()
        }
    }

    /// The same event on another day is another meeting.
    private func key(_ event: EventModel) -> String { "\(event.id)|\(event.start.timeIntervalSince1970)" }

    #if NOTCHFUN_SOAK
    func showDemo(title: String) {
        let start = Date().addingTimeInterval(Self.leadTime)
        current = EventModel(
            id: "demo", start: start, end: start.addingTimeInterval(1800), title: title,
            location: nil, notes: nil, url: nil, isAllDay: false, type: .event(.accepted),
            calendar: .init(id: "demo", account: "", title: "Demo", color: .systemBlue, isSubscribed: false, isReminder: false),
            participants: [], timeZone: nil, hasRecurrenceRules: false, priority: nil,
            meetingLink: .init(url: URL(string: "https://meet.google.com/abc-defg-hij")!, service: .meet))
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .meeting)
    }
    #endif

    private func announce(_ event: EventModel) {
        guard isEnabled, event.start > Date() else { return }
        announcedIDs.insert(key(event))
        current = event
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .meeting)
    }
}
