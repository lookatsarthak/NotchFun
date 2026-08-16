//
//  ClipboardMonitor.swift
//  boringNotch
//
//  Polling approach adapted from Maccy (https://github.com/p0deje/Maccy),
//  Maccy/Clipboard.swift. MIT License © Alex Rodionov.
//  See THIRD_PARTY_LICENSES.
//

import AppKit
import Foundation
import os

/// Watches `NSPasteboard.general` for new copies.
///
/// AppKit offers no change notification for the pasteboard, so this polls
/// `changeCount` on a timer — the same approach every clipboard manager uses. The
/// timer only exists while the feature is enabled, carries a tolerance so the system
/// can coalesce its wakeups, and is suspended outright on screen lock and system
/// sleep, so a user who never turns the feature on pays nothing.
@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private static let logger = Logger(subsystem: "io.github.lookatsarthak.notchfun", category: "ClipboardMonitor")

    typealias OnCapture = (ClipboardItem) -> Void

    private let pasteboard: NSPasteboard
    private let blobStore: ClipboardBlobStore

    private var timer: Timer?
    private var changeCount: Int
    private var isSuspended = false
    /// Background processing is chained rather than run concurrently, so two copies in
    /// quick succession are still recorded in the order they were made.
    private var processingChain: Task<Void, Never>?

    private(set) var isRunning = false
    private var config: ClipboardCaptureConfig = .default
    private var onCapture: OnCapture?

    init(pasteboard: NSPasteboard = .general, blobStore: ClipboardBlobStore = .shared) {
        self.pasteboard = pasteboard
        self.blobStore = blobStore
        self.changeCount = pasteboard.changeCount
    }

    // MARK: - Lifecycle

    func setHandler(_ handler: @escaping OnCapture) {
        onCapture = handler
    }

    func start(config: ClipboardCaptureConfig) {
        self.config = config
        guard !isRunning else {
            reschedule()
            return
        }
        isRunning = true
        // Adopt the current state so whatever was already on the pasteboard before the
        // feature was switched on is not swept into the history.
        changeCount = pasteboard.changeCount
        reschedule()
        Self.logger.notice("Clipboard monitor started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        Self.logger.notice("Clipboard monitor stopped")
    }

    /// Pauses polling without forgetting that the feature is on. Used for screen lock
    /// and system sleep, where nothing can be copied anyway.
    func suspend() {
        guard isRunning, !isSuspended else { return }
        isSuspended = true
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard isRunning, isSuspended else { return }
        isSuspended = false
        // Skip anything copied while suspended rather than back-filling on wake.
        changeCount = pasteboard.changeCount
        reschedule()
    }

    func update(config: ClipboardCaptureConfig) {
        let intervalChanged = config.pollInterval != self.config.pollInterval
        self.config = config
        if isRunning, !isSuspended, intervalChanged { reschedule() }
    }

    // MARK: - Polling

    private func reschedule() {
        timer?.invalidate()
        guard isRunning, !isSuspended else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: config.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Lets the system align our wakeup with others instead of firing on its own.
        timer.tolerance = config.pollInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let current = pasteboard.changeCount
        guard current != changeCount else { return }
        changeCount = current

        // Reading the pasteboard has to happen here, synchronously, before the user's
        // next copy replaces it. Everything expensive — hashing, blob writes, title
        // extraction — is handed to a background task so the tick stays short and the
        // main thread stays free for the notch's animations.
        guard let snapshot = ClipboardCapture.snapshot(
            from: pasteboard,
            sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            config: config
        ) else { return }

        let blobStore = self.blobStore
        let previous = processingChain
        processingChain = Task.detached(priority: .utility) { [weak self] in
            _ = await previous?.value
            let item = ClipboardCapture.makeItem(from: snapshot, blobStore: blobStore)
            guard let item else { return }
            await self?.deliver(item)
        }
    }

    private func deliver(_ item: ClipboardItem) {
        onCapture?(item)
    }

    /// Re-syncs `changeCount` after the app itself writes to the pasteboard, so the
    /// next tick has nothing to react to. The `.fromNotchFun` marker already covers
    /// this, but syncing avoids even parsing our own write.
    func acknowledgeSelfCopy() {
        changeCount = pasteboard.changeCount
    }
}
