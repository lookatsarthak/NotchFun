//
//  CaffeineManager.swift
//  boringNotch
//

import AppKit
import Combine
import Foundation
import os

/// Owns the one power assertion and the session that justifies it.
///
/// The invariant this whole type exists to protect: **an assertion is held if and only
/// if `session` is non-nil**. An assertion without a session is a Mac that never sleeps
/// for no visible reason, which is the worst possible bug in a feature like this. Every
/// mutation goes through `apply(_:)` so the two can never drift apart.
@MainActor
final class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()

    private static let logger = Logger(subsystem: "io.github.lookatsarthak.notchfun", category: "Caffeine")

    /// Emitted whenever caffeine turns on or off, so the UI can show a notification
    /// without polling.
    enum Change: Equatable {
        case activated(CaffeineSession)
        case deactivated(reason: DeactivationReason)
    }

    enum DeactivationReason: Equatable {
        case user
        case expired
        case boundAppQuit(name: String)
        case failed
    }

    @Published private(set) var session: CaffeineSession?
    /// Ticks while a timed session is running, so a countdown can redraw.
    @Published private(set) var remainingLabel: String?

    let changes = PassthroughSubject<Change, Never>()

    var isActive: Bool { session != nil }

    private let assertion: PowerAssertionHolding
    private let store: CaffeineSessionStoring
    private var countdown: Timer?
    private var observers: [Any] = []
    private var batteryObserverID: Int?
    private var autoTriggerEnabled: (@Sendable (AutoTrigger) -> Bool)?
    private var autoTriggerMode: (@Sendable () -> CaffeineMode)?

    init(assertion: PowerAssertionHolding, store: CaffeineSessionStoring) {
        self.assertion = assertion
        self.store = store
    }

    convenience init() {
        self.init(assertion: IOPMPowerAssertion(), store: CaffeineSessionStore())
    }

    // MARK: - Lifecycle

    /// Restores a session persisted from a previous launch, dropping it if it expired
    /// while the app was not running.
    func restore(now: Date = .now) {
        guard let saved = store.load() else { return }

        if saved.isExpired(at: now) {
            Self.logger.notice("Discarding caffeine session that expired while not running")
            store.save(nil)
            return
        }

        if let bundleID = saved.boundAppBundleID, !Self.isAppRunning(bundleID: bundleID) {
            Self.logger.notice("Discarding caffeine session; its app is no longer running")
            store.save(nil)
            return
        }

        apply(saved, announce: false)
    }

    /// What can switch caffeine on by itself.
    enum AutoTrigger: Sendable {
        case powerConnected
        case externalDisplay
    }

    /// Records what may switch caffeine on by itself.
    ///
    /// Only the decision lives here. Watching the power adapter and the screens is the
    /// app layer's job, because this type is compiled into the test bundle, which links
    /// neither Defaults nor the battery manager - keeping it that way is what lets these
    /// rules be tested at all.
    func configureAutoTriggers(
        isEnabled: @escaping @Sendable (AutoTrigger) -> Bool,
        mode: @escaping @Sendable () -> CaffeineMode
    ) {
        autoTriggerEnabled = isEnabled
        autoTriggerMode = mode
    }

    /// Turns caffeine on when the trigger appears, and off again only if we were the one
    /// who turned it on.
    func handleAutoTrigger(_ trigger: AutoTrigger, active: Bool) {
        guard autoTriggerEnabled?(trigger) == true else { return }

        if active {
            guard !isActive else { return }
            startedAutomatically = true
            activate(mode: autoTriggerMode?() ?? .displayAwake, duration: .indefinite)
        } else if startedAutomatically {
            deactivate()
        }
    }

    /// Hooks up sleep/wake and app-termination observers. Called once at launch.
    func startObserving() {
        let center = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            Task { @MainActor in
                self?.handleAppTerminated(bundleID: bundleID, name: app.localizedName ?? bundleID)
            }
        })
    }

    // MARK: - Commands

    @discardableResult
    func activate(mode: CaffeineMode, duration: CaffeineDuration, now: Date = .now) -> Bool {
        let new = CaffeineSession(mode: mode, duration: duration, startedAt: now)
        return apply(new, announce: true)
    }

    func deactivate(reason: DeactivationReason = .user) {
        guard session != nil else { return }
        assertion.release()
        session = nil
        startedAutomatically = false
        remainingLabel = nil
        stopCountdown()
        store.save(nil)
        Self.logger.notice("Caffeine off (\(String(describing: reason), privacy: .public))")
        changes.send(.deactivated(reason: reason))
    }

    /// Convenience for a single button: on if off, off if on.
    @discardableResult
    func toggle(mode: CaffeineMode, duration: CaffeineDuration) -> Bool {
        if isActive {
            deactivate(reason: .user)
            return false
        }
        return activate(mode: mode, duration: duration)
    }

    /// Extends or shortens a running session without dropping the assertion.
    @discardableResult
    func reschedule(to duration: CaffeineDuration, now: Date = .now) -> Bool {
        guard let current = session else { return false }
        return activate(mode: current.mode, duration: duration, now: now)
    }

    // MARK: - Events

    /// Assertions do not reliably survive sleep, so re-take it on wake — and check
    /// first whether the session should have ended during the sleep.
    func handleWake(now: Date = .now) {
        guard let current = session else { return }

        if current.isExpired(at: now) {
            deactivate(reason: .expired)
            return
        }
        if !assertion.hold(mode: current.mode, reason: Self.assertionReason) {
            Self.logger.error("Could not re-take the power assertion after wake")
            deactivate(reason: .failed)
            return
        }
        Self.logger.notice("Re-took power assertion after wake")
        refreshCountdown(now: now)
    }

    func handleAppTerminated(bundleID: String, name: String) {
        guard let current = session, current.boundAppBundleID == bundleID else { return }
        deactivate(reason: .boundAppQuit(name: name))
    }

    /// Called by the countdown timer; also safe to call directly in tests.
    func tick(now: Date = .now) {
        guard let current = session else { return }
        if current.isExpired(at: now) {
            deactivate(reason: .expired)
            return
        }
        remainingLabel = current.remainingLabel(at: now)
    }

    // MARK: - Internals

    private static let assertionReason = "NotchFun caffeine"

    /// True when *this* turned caffeine on, rather than the user.
    ///
    /// It decides whether unplugging may turn it off again. A session the user started
    /// deliberately is never cancelled by hardware changing underneath them - having
    /// your Mac decide to stop staying awake because you moved to battery is a worse
    /// surprise than it staying on.
    private var startedAutomatically = false

    /// The single place the assertion and the session are set together.
    @discardableResult
    private func apply(_ new: CaffeineSession, announce: Bool) -> Bool {
        guard assertion.hold(mode: new.mode, reason: Self.assertionReason) else {
            Self.logger.error("Could not take the power assertion")
            // Leave no half state behind.
            session = nil
            remainingLabel = nil
            stopCountdown()
            store.save(nil)
            changes.send(.deactivated(reason: .failed))
            return false
        }

        session = new
        store.save(new)
        refreshCountdown(now: new.startedAt)
        Self.logger.notice("Caffeine on — \(new.mode.rawValue, privacy: .public), \(new.duration.title, privacy: .public)")
        if announce { changes.send(.activated(new)) }
        return true
    }

    private func refreshCountdown(now: Date) {
        stopCountdown()
        guard let current = session else { return }
        remainingLabel = current.remainingLabel(at: now)
        guard current.expiresAt != nil else { return }

        // weak self, and self rather than .shared: an injected instance must tick
        // itself, not the singleton.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        countdown = timer
    }

    private func stopCountdown() {
        countdown?.invalidate()
        countdown = nil
    }

    private static func isAppRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Releases the assertion on quit. `applicationWillTerminate` is synchronous, so
    /// this cannot be async.
    func releaseForTermination() {
        assertion.release()
    }
}
