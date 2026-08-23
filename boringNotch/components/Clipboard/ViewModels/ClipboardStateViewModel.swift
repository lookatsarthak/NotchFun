//
//  ClipboardStateViewModel.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation
import os

/// Owns the clipboard history and mediates between the monitor, disk, and the UI.
///
/// Follows the shape of `ShelfStateViewModel`: a `@MainActor` singleton `ObservableObject`
/// that writes through to a persistence service on mutation.
///
/// One rule is load-bearing for the notch's smoothness: **this object must publish
/// nothing while the clipboard tab is not on screen.** `ContentView` is mounted for the
/// entire life of the app and already observes six `ObservableObject`s, so a
/// `@Published` mutation on every system-wide copy would invalidate the notch's view
/// tree every time the user pressed Cmd-C anywhere on the Mac. Captures therefore land
/// in the non-published `history` and only get projected into `visibleItems` while the
/// tab is presenting.
@MainActor
final class ClipboardStateViewModel: ObservableObject {
    static let shared = ClipboardStateViewModel()

    private static let logger = Logger(subsystem: "io.github.lookatsarthak.notchfun", category: "ClipboardState")

    /// The full history. Deliberately *not* `@Published`.
    private var history = ClipboardHistory()

    /// Projection of `history` for the UI. Only ever assigned while presenting.
    @Published private(set) var visibleItems: [ClipboardItem] = []

    /// True while the clipboard tab is on screen.
    private(set) var isPresenting = false
    /// Set when a capture arrives off-screen, so the next present refreshes.
    private var needsRefresh = false

    private let monitor: ClipboardMonitor
    private let persistence: ClipboardPersistenceService
    private let blobStore: ClipboardBlobStore
    private var preferenceTasks: [Task<Void, Never>] = []

    /// Which apps entries were copied from, most frequent first.
    ///
    /// Read on demand by Settings rather than published: the notch never needs it, and
    /// republishing on every copy is exactly what `visibleItems` exists to avoid.
    var sourceAppFrequencies: [String] {
        var counts: [String: Int] = [:]
        for item in history.items {
            guard let id = item.appBundleID else { continue }
            counts[id, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    var isEmpty: Bool { history.items.isEmpty }
    var itemCount: Int { history.items.count }
    var unpinnedCount: Int { history.unpinned.count }

    /// Default arguments are evaluated in a nonisolated context, so the shared
    /// dependencies are resolved in the body instead — referencing a `@MainActor`
    /// singleton from a default argument is an error in the Swift 6 language mode.
    convenience init() {
        self.init(monitor: .shared, persistence: .shared, blobStore: .shared)
    }

    init(
        monitor: ClipboardMonitor,
        persistence: ClipboardPersistenceService,
        blobStore: ClipboardBlobStore
    ) {
        self.monitor = monitor
        self.persistence = persistence
        self.blobStore = blobStore
    }

    // MARK: - Lifecycle

    /// Called once at app launch.
    func bootstrap() {
        monitor.setHandler { [weak self] item in
            // Restart the auto-clear countdown from the copy the user just made, rather
            // than from whenever the setting last changed. Lives here, not in the
            // monitor: the monitor is compiled into the test bundle and stays free of
            // preferences and services.
            ClipboardAutoClearService.shared.noteCopy()
            self?.capture(item)
        }
        observePreferences()
    }

    private func observePreferences() {
        preferenceTasks.forEach { $0.cancel() }
        preferenceTasks = [
            Task { [weak self] in
                for await enabled in Defaults.updates(.clipboardHistoryEnabled) {
                    guard let self else { return }
                    enabled ? self.enable() : self.disable()
                }
            },
            // Every key `currentConfig` reads has to be here, or changing it in Settings
            // does nothing until the app is restarted. That is not hypothetical: the
            // privacy toggle and the ignore list both looked broken because only the
            // poll interval was being watched.
            Task { [weak self] in
                for await _ in Defaults.updates(
                    [
                        .clipboardCheckInterval,
                        .clipboardMaxPayloadMB,
                        .clipboardIgnoreUniversalClipboard,
                        .clipboardSkipSensitiveText,
                        .clipboardIgnoredApps,
                    ],
                    initial: false
                ) {
                    self?.monitor.update(config: Self.currentConfig)
                }
            },
            Task { [weak self] in
                for await size in Defaults.updates(.clipboardHistorySize, initial: false) {
                    self?.applyHistoryLimit(max(1, size))
                }
            }
        ]
    }

    private func enable() {
        // Load lazily: a user who never turns this on never touches the disk.
        if history.items.isEmpty {
            history = ClipboardHistory(items: persistence.load())
            blobStore.pruneOrphans(keeping: history.items)
        }
        monitor.start(config: Self.currentConfig)
        needsRefresh = true
        refreshIfPresenting()
    }

    private func disable() {
        monitor.stop()
        visibleItems = []
    }

    func suspendMonitoring() { monitor.suspend() }
    func resumeMonitoring() { monitor.resume() }

    /// Writes any pending changes immediately.
    func flush() async {
        await persistence.flush(history.items)
    }

    /// Blocking variant for `applicationWillTerminate`.
    func flushSynchronously() {
        persistence.flushSynchronously(history.items)
    }

    static var currentConfig: ClipboardCaptureConfig {
        ClipboardCaptureConfig(
            pollInterval: max(0.1, Defaults[.clipboardCheckInterval]),
            maxHistorySize: max(1, Defaults[.clipboardHistorySize]),
            maxPayloadBytes: max(1, Defaults[.clipboardMaxPayloadMB]) * 1024 * 1024,
            ignoreUniversalClipboard: Defaults[.clipboardIgnoreUniversalClipboard],
            skipSensitiveText: Defaults[.clipboardSkipSensitiveText],
            ignoredAppBundleIDs: Set(Defaults[.clipboardIgnoredApps])
        )
    }

    // MARK: - Presentation

    func beginPresenting() {
        isPresenting = true
        needsRefresh = true
        refreshIfPresenting()
    }

    func endPresenting() {
        isPresenting = false
    }

    private func refreshIfPresenting() {
        guard isPresenting, needsRefresh else { return }
        needsRefresh = false
        visibleItems = history.items
    }

    // MARK: - Capture

    private func capture(_ item: ClipboardItem) {
        let outcome = history.add(item, maxSize: max(1, Defaults[.clipboardHistorySize]))

        // Reclaim disk for anything the size limit pushed out.
        if !outcome.evicted.isEmpty {
            blobStore.delete(outcome.evicted.flatMap(\.contents))
        }

        persistence.scheduleSave(history.items)
        needsRefresh = true
        refreshIfPresenting()
    }

    // MARK: - Mutation

    func togglePin(id: UUID) {
        guard history.togglePin(id: id) != nil else { return }
        persistence.scheduleSave(history.items)
        needsRefresh = true
        refreshIfPresenting()
    }

    func delete(id: UUID) {
        guard let removed = history.remove(id: id) else { return }
        blobStore.delete(removed.contents)
        persistence.scheduleSave(history.items)
        needsRefresh = true
        refreshIfPresenting()
    }

    func clearUnpinned() {
        let removed = history.clearUnpinned()
        guard !removed.isEmpty else { return }
        blobStore.delete(removed.flatMap(\.contents))
        persistence.scheduleSave(history.items)
        needsRefresh = true
        refreshIfPresenting()
    }

    func clearAll() {
        history.clearAll()
        persistence.deleteEverything()
        needsRefresh = true
        refreshIfPresenting()
    }

    private func applyHistoryLimit(_ size: Int) {
        let evicted = history.enforceLimit(size)
        guard !evicted.isEmpty else { return }
        blobStore.delete(evicted.flatMap(\.contents))
        persistence.scheduleSave(history.items)
        needsRefresh = true
        refreshIfPresenting()
    }

    // MARK: - Putting an entry back on the pasteboard

    /// Writes `item` to the general pasteboard.
    ///
    /// Stamps `.fromNotchFun` so the monitor recognises the write as its own and
    /// does not record it again — without this, selecting an entry would re-add it on
    /// the next poll and the history would slowly fill with copies of itself.
    func copyToPasteboard(_ item: ClipboardItem) {
        guard ClipboardPasteboardWriter.write(item, to: .general, blobStore: blobStore,
                                              cleanLinks: Defaults[.clipboardCleanLinks]) else {
            Self.logger.error("Failed to write clipboard entry to the pasteboard")
            return
        }

        monitor.acknowledgeSelfCopy()

        // Re-copying counts as a use: bump the entry to the top so the most recently
        // used clips stay reachable.
        promote(item)
    }

    /// Copies an entry with its formatting removed. Falls back to a normal copy when the
    /// entry has no text - an image has no plain form, and doing nothing would look broken.
    func copyToPasteboardAsPlainText(_ item: ClipboardItem) {
        if ClipboardPasteboardWriter.writePlainText(item, blobStore: blobStore,
                                                    cleanLinks: Defaults[.clipboardCleanLinks]) {
            ClipboardMonitor.shared.acknowledgeSelfCopy()
        } else {
            copyToPasteboard(item)
        }
    }

    private func promote(id: UUID) {
        guard let existing = history.remove(id: id) else { return }
        var updated = existing
        updated.lastCopiedAt = .now
        history.add(updated, maxSize: max(1, Defaults[.clipboardHistorySize]))
        persistence.scheduleSave(history.items)
        needsRefresh = true
        refreshIfPresenting()
    }

    private func promote(_ item: ClipboardItem) { promote(id: item.id) }

    // MARK: - Content access

    func data(for ref: ClipboardContentRef) -> Data? { blobStore.data(for: ref) }
    func text(of item: ClipboardItem) -> String? { item.text(using: blobStore) }
    func imageData(of item: ClipboardItem) -> Data? { item.imageData(using: blobStore) }
    func fileURLs(of item: ClipboardItem) -> [URL] { item.fileURLs(using: blobStore) }
}
