//
//  AgentStatusCenter.swift
//  NotchFun
//

import Foundation

/// What Claude Code is doing, from the hooks' `notchfun://agent` links, for the face and
/// the "needs you" banner.
///
/// Event-driven throughout. The only timer is a single one set for the next expiry
/// ("done" fading after a few seconds, a silent session timing out), and there is none
/// while no session has anything to say.
@MainActor
@Observable
final class AgentStatusCenter {
    static let shared = AgentStatusCenter()

    /// The most urgent state across sessions, or nil.
    private(set) var headline: AgentBoard.State?
    /// Sessions waiting for you.
    private(set) var waitingCount = 0
    /// True for a moment after any session finishes, even while another is working or
    /// waiting, so a finish is never hidden behind a busier session.
    private(set) var celebrating = false

    /// What the face shows right now: a fresh finish first, then the most urgent state.
    var shown: AgentBoard.State? { celebrating ? .done : headline }

    /// How long the attention glyph stays beside the notch when the face can't be seen.
    static let bannerDuration: TimeInterval = 6
    /// How long a finish shows.
    static let celebrationDuration: TimeInterval = 2.5

    @ObservationIgnored private var board = AgentBoard()
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var celebrationTask: Task<Void, Never>?

    private init() {}

    func handle(_ report: ClaudeCodeHooks.Report, session: String, at now: Date = Date()) {
        let waitingBefore = board.counts[.waiting] ?? 0
        switch report {
        case .end: board.apply(state: nil, ended: true, session: session, at: now)
        case .working: board.apply(state: .working, session: session, at: now)
        case .waiting: board.apply(state: .waiting, session: session, at: now)
        case .done: board.apply(state: .done, session: session, at: now)
        case .error: board.apply(state: .error, session: session, at: now)
        }
        board.prune(at: now)
        publish()

        // The glyph beside the notch is for a session starting to wait or finishing, not
        // for every repeat. ContentView shows it only when the face itself isn't visible.
        if report == .waiting, waitingCount > waitingBefore {
            BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .agent)
        }
        if report == .done { celebrate() }
        scheduleExpiry()
    }

    private func celebrate() {
        celebrating = true
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .agent)
        celebrationTask?.cancel()
        celebrationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.celebrationDuration))
            guard !Task.isCancelled else { return }
            self?.celebrating = false
        }
    }

    private func publish() {
        let headline = board.headline
        let waiting = board.counts[.waiting] ?? 0
        if headline != self.headline { self.headline = headline }
        if waiting != waitingCount { waitingCount = waiting }
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let next = board.nextExpiry() else { expiryTask = nil; return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.05, next.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            self.board.prune(at: Date())
            self.publish()
            self.scheduleExpiry()
        }
    }

    #if NOTCHFUN_SOAK
    /// Drops every session, for tests.
    func reset() {
        board = AgentBoard()
        publish()
        scheduleExpiry()
    }
    #endif
}
