//
//  ClipboardKeyCaptureService.swift
//  boringNotch
//
//  Modelled on observers/MediaKeyInterceptor.swift, which is the app's existing,
//  proven CGEvent tap.
//

import AppKit
import Carbon.HIToolbox
import Defaults
import Foundation
import os

/// Captures keystrokes for the clipboard tab.
///
/// The notch window is a `NSPanel` with `canBecomeKey == false` living in a private
/// CGS space, so a SwiftUI `TextField` inside it can never receive a keystroke.
/// Rather than change that — the window layer is load-bearing for the whole app — this
/// takes the same route as the HUD replacement: a CGEvent tap, sharing the one
/// Accessibility grant the app already asks for.
///
/// The tap exists **only** while the clipboard tab is actually on screen. A tap that
/// does not exist cannot swallow anyone's keyboard, which is the single most important
/// safety property here.
@MainActor
final class ClipboardKeyCaptureService {
    static let shared = ClipboardKeyCaptureService()

    private static let logger = Logger(subsystem: "io.github.lookatsarthak.notchfun", category: "ClipboardKeys")

    typealias Handler = (ClipboardKeyEvent) -> Void

    /// Hard ceiling on how long a tap may live, as a backstop against any path that
    /// fails to tear it down.
    private static let maxLifetime: TimeInterval = 180

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: TapThread?
    private var lifetimeTask: Task<Void, Never>?
    private var handler: Handler?

    private(set) var isRunning = false

    /// Read from the tap thread, written from the main actor.
    private let active = OSAllocatedUnfairLock(initialState: false)

    // MARK: - Lifecycle

    /// - Returns: whether capture actually started. `false` means the caller should
    ///   fall back to mouse-only operation.
    @discardableResult
    func start(handler: @escaping Handler) -> Bool {
        guard !isRunning else { return true }
        guard Defaults[.clipboardKeyboardNavigation] else { return false }

        // Trust must be checked in this process — the tap is installed here.
        // Never prompts: typing in a panel is not worth interrupting the user for.
        guard ClipboardAccessibility.isTrusted else {
            Self.logger.notice("Keyboard capture unavailable: Accessibility not granted")
            return false
        }

        self.handler = handler

        let thread = TapThread()
        thread.start()
        guard thread.waitUntilReady(timeout: 2) else {
            Self.logger.error("Keyboard capture thread failed to start")
            return false
        }
        tapThread = thread

        // tapDisabledBy* events are delivered to the callback regardless of the mask,
        // so only the two we actually want to inspect are listed here.
        var mask: UInt64 = 0
        mask |= 1 << UInt64(CGEventType.keyDown.rawValue)
        mask |= 1 << UInt64(CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<ClipboardKeyCaptureService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            Self.logger.error("Failed to create keyboard tap")
            teardownThread()
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        thread.add(source: source)

        eventTap = tap
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)

        active.withLock { $0 = true }
        isRunning = true

        lifetimeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxLifetime))
            guard !Task.isCancelled else { return }
            Self.logger.error("Keyboard capture exceeded its maximum lifetime; forcing teardown")
            self?.stop()
        }

        Self.logger.notice("Keyboard capture started")
        return true
    }

    func stop() {
        guard isRunning else { return }
        // Flip the flag first: from this instant the callback passes everything
        // through, even if teardown of the mach port takes a moment.
        active.withLock { $0 = false }
        isRunning = false

        lifetimeTask?.cancel()
        lifetimeTask = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        teardownThread()
        eventTap = nil
        runLoopSource = nil
        handler = nil

        Self.logger.notice("Keyboard capture stopped")
    }

    private func teardownThread() {
        if let tapThread, let runLoopSource {
            tapThread.remove(source: runLoopSource)
        }
        tapThread?.stop()
        tapThread = nil
    }

    /// True when a password field somewhere has enabled secure input. Taps observe
    /// nothing in that state, so the UI needs to explain itself rather than look broken.
    static var isSecureInputActive: Bool { IsSecureEventInputEnabled() }

    // MARK: - Tap callback (runs on the tap thread)

    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that takes too long or when the user forces input;
        // re-enable immediately or keyboard capture silently dies.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor [weak self] in
                guard let self, let tap = self.eventTap, self.isRunning else { return }
                Self.logger.error("Keyboard tap was disabled by the system; re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }

        guard active.withLock({ $0 }), type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let action = ClipboardKeyInterpreter.interpret(
            keyCode: keyCode,
            flags: event.flags,
            text: ClipboardKeyInterpreter.text(from: event)
        ) else {
            return Unmanaged.passUnretained(event)
        }

        Task { @MainActor [weak self] in
            self?.handler?(action)
        }

        // Consumed: swallow it so it does not also reach the frontmost app.
        return nil
    }

}

// MARK: - Tap thread

/// A thread with a run loop dedicated to the event tap.
///
/// The tap deliberately does not run on the main run loop: typing arrives at ~10
/// events/second and the main actor is busy driving the notch's spring animations, so
/// main-thread dispatch would both feel laggy and risk `tapDisabledByTimeout`
/// mid-word. (The media-key tap gets away with the main run loop because media keys
/// arrive a few times a second at most.)
private final class TapThread: Thread, @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop?
    private let lock = NSLock()

    override func main() {
        lock.lock()
        runLoop = CFRunLoopGetCurrent()
        lock.unlock()
        ready.signal()

        // A run loop with no sources returns immediately, so keep looping until
        // cancelled rather than calling CFRunLoopRun() once.
        while !isCancelled {
            CFRunLoopRunInMode(.defaultMode, 0.25, false)
        }
    }

    func waitUntilReady(timeout: TimeInterval) -> Bool {
        ready.wait(timeout: .now() + timeout) == .success
    }

    func add(source: CFRunLoopSource?) {
        lock.lock(); let loop = runLoop; lock.unlock()
        guard let loop, let source else { return }
        CFRunLoopAddSource(loop, source, .commonModes)
        CFRunLoopWakeUp(loop)
    }

    func remove(source: CFRunLoopSource?) {
        lock.lock(); let loop = runLoop; lock.unlock()
        guard let loop, let source else { return }
        CFRunLoopRemoveSource(loop, source, .commonModes)
        CFRunLoopWakeUp(loop)
    }

    func stop() {
        cancel()
        lock.lock(); let loop = runLoop; lock.unlock()
        if let loop { CFRunLoopWakeUp(loop) }
    }
}
