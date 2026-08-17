//
//  CaffeineSession.swift
//  boringNotch
//

import Foundation

/// A single caffeine session.
///
/// Deliberately stores an absolute `expiresAt` rather than a countdown or a `Timer`.
/// A `Timer` does not fire while the Mac is asleep, so a one-hour session started
/// before a two-hour nap would silently survive the sleep and keep running — the user
/// would find caffeine still on hours after they expected it off. Comparing against
/// wall-clock time on wake makes sleep a non-event.
struct CaffeineSession: Codable, Equatable, Sendable {
    var mode: CaffeineMode
    var duration: CaffeineDuration
    var startedAt: Date
    /// Absolute end time. `nil` for indefinite and app-bound sessions.
    var expiresAt: Date?

    init(mode: CaffeineMode, duration: CaffeineDuration, startedAt: Date = .now) {
        self.mode = mode
        self.duration = duration
        self.startedAt = startedAt
        self.expiresAt = duration.timeInterval.map { startedAt.addingTimeInterval($0) }
    }

    /// The app this session is tied to, if any.
    var boundAppBundleID: String? {
        if case .whileAppRunning(let bundleID, _) = duration { return bundleID }
        return nil
    }

    func isExpired(at now: Date = .now) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// Seconds left, or `nil` when the session has no fixed end.
    func remaining(at now: Date = .now) -> TimeInterval? {
        guard let expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSince(now))
    }

    /// Countdown for the notch, e.g. "42m" or "1:05".
    func remainingLabel(at now: Date = .now) -> String? {
        guard let remaining = remaining(at: now) else { return nil }
        let total = Int(remaining.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d", hours, minutes) }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }
}
