//
//  AgentBoard.swift
//  NotchFun
//

import Foundation

/// What each running Claude Code session last reported, and the one state the face shows.
///
/// Sessions report through hooks that open `notchfun://agent?state=…&pid=…`. The pid is
/// the session's own process, so two terminals or the desktop app running side by side
/// stay apart. Pure and clock-injected, so the rules can be tested:
///
/// - **The face shows the most urgent state**: waiting for you, then an error, then
///   working, then a just-finished session.
/// - **"Done" lasts a few seconds** and then the session goes quiet.
/// - **Nothing lasts forever.** A session that crashes mid-task never says it stopped, so
///   "working" expires after a long silence, and every other state after a while longer.
struct AgentBoard: Equatable, Sendable {
    enum State: String, Sendable, CaseIterable {
        case working, waiting, done, error

        /// Higher wins when several sessions report at once.
        var urgency: Int {
            switch self {
            case .waiting: return 3
            case .error: return 2
            case .working: return 1
            case .done: return 0
            }
        }
    }

    struct Session: Equatable, Sendable {
        var state: State
        /// When this state began.
        var since: Date
        /// The latest report of this state. Working sessions report on every tool call.
        var lastSeen: Date
    }

    /// How long "done" shows before the session goes quiet.
    static let doneLifetime: TimeInterval = 5
    /// A working session that has said nothing for this long has probably died. Tool calls
    /// report as they happen, so a live session rarely goes this quiet.
    static let workingLifetime: TimeInterval = 15 * 60
    /// Waiting and error stay up until the session moves on or ends, within reason.
    static let attentionLifetime: TimeInterval = 60 * 60

    private(set) var sessions: [String: Session] = [:]

    /// One report. `ended` removes the session.
    mutating func apply(state: State?, ended: Bool = false, session: String, at now: Date) {
        if ended {
            sessions[session] = nil
            return
        }
        guard let state else { return }
        // A repeat of the same state keeps when it began and only notes it's still alive.
        if var existing = sessions[session], existing.state == state {
            existing.lastSeen = now
            sessions[session] = existing
            return
        }
        sessions[session] = Session(state: state, since: now, lastSeen: now)
    }

    /// Drops what has expired. Returns true if anything changed.
    @discardableResult
    mutating func prune(at now: Date) -> Bool {
        let before = sessions
        sessions = sessions.filter { _, session in Self.expiry(of: session) > now }
        return sessions != before
    }

    /// The state the face shows, or nil when no session has anything to say.
    var headline: State? {
        sessions.values.map(\.state).max { $0.urgency < $1.urgency }
    }

    /// How many sessions are in each state, for the hover summary.
    var counts: [State: Int] {
        sessions.values.reduce(into: [:]) { $0[$1.state, default: 0] += 1 }
    }

    /// When the next state will expire, so a single timer can be set for it instead of a
    /// repeating one. Nil when nothing will.
    func nextExpiry() -> Date? {
        sessions.values.map(Self.expiry).min()
    }

    /// "Done" from when it finished; the others from the last time they were heard from.
    private static func expiry(of session: Session) -> Date {
        switch session.state {
        case .done: return session.since.addingTimeInterval(doneLifetime)
        case .working: return session.lastSeen.addingTimeInterval(workingLifetime)
        case .waiting, .error: return session.lastSeen.addingTimeInterval(attentionLifetime)
        }
    }
}
