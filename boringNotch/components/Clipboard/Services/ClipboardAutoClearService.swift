//
//  ClipboardAutoClearService.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation

/// Empties the *system* clipboard on a timer, or when the Mac sleeps or locks.
///
/// Deliberately separate from the history. This clears what ⌘V would paste; it never
/// touches saved entries. Those are two different promises and conflating them is the
/// main way a feature like this goes wrong for people.
///
/// Every trigger is off by default, and with all of them off no timer is scheduled and
/// no observers are installed, so the feature costs nothing until it is asked for.
@MainActor
final class ClipboardAutoClearService {
    static let shared = ClipboardAutoClearService()

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lockObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var isObserving = false

    /// Called by the monitor after it sees a new copy, to restart the countdown.
    func noteCopy() {
        scheduleTimer()
    }

    func start() {
        guard !isObserving else { return }
        isObserving = true

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearIfEnabled(Defaults[.clipboardClearOnSleep]) }
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearIfEnabled(Defaults[.clipboardClearOnDisplaySleep]) }
        })

        // Screen lock is not on NSWorkspace's centre; it is a distributed notification.
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearIfEnabled(Defaults[.clipboardClearOnLock]) }
        }

        // React to the delay being changed while the app is running.
        Defaults.publisher(.clipboardAutoClearDelay)
            .sink { [weak self] _ in
                Task { @MainActor in self?.scheduleTimer() }
            }
            .store(in: &cancellables)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        if let lockObserver {
            DistributedNotificationCenter.default().removeObserver(lockObserver)
            self.lockObserver = nil
        }
        cancellables.removeAll()
        isObserving = false
    }

    // MARK: - Internals

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil

        let delay = Defaults[.clipboardAutoClearDelay]
        guard delay > 0 else { return }

        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        }
        // A clipboard that empties a few seconds late is fine, and a loose tolerance
        // lets the timer coalesce with other wake-ups instead of waking the CPU alone.
        timer.tolerance = min(5, delay * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func clearIfEnabled(_ enabled: Bool) {
        guard enabled else { return }
        clear()
    }

    private func clear() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastClearedChangeCount else { return }
        pasteboard.clearContents()
        lastClearedChangeCount = pasteboard.changeCount
        // Tell the monitor this was us, so an empty pasteboard is not recorded as a copy.
        ClipboardMonitor.shared.acknowledgeSelfCopy()
    }

    private var lastClearedChangeCount: Int = -1
}
