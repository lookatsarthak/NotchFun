//
//  ClipboardHistory.swift
//  boringNotch
//
//  Deduplication semantics follow Maccy (https://github.com/p0deje/Maccy),
//  Maccy/Observables/History.swift. MIT License © Alex Rodionov.
//  See THIRD_PARTY_LICENSES.
//

import Foundation

/// The in-memory history, ordered most-recent-first.
///
/// A plain value type with no actor isolation, no `@Published`, and no I/O, so the
/// add/dedupe/evict rules can be tested directly. `ClipboardStateViewModel` owns an
/// instance and is responsible for persistence and for publishing to SwiftUI.
struct ClipboardHistory {
    private(set) var items: [ClipboardItem] = []

    /// What `add` did, so the caller knows which blobs to delete and when to save.
    struct AddOutcome {
        /// The item as it now exists in the history.
        var stored: ClipboardItem
        /// True when this replaced an existing duplicate rather than adding a new row.
        var wasDuplicate: Bool
        /// Items dropped by the size limit — their blobs should be deleted.
        var evicted: [ClipboardItem] = []
    }

    init(items: [ClipboardItem] = []) {
        self.items = items
    }

    var pinned: [ClipboardItem] { items.filter(\.isPinned) }
    var unpinned: [ClipboardItem] { items.filter { !$0.isPinned } }

    // MARK: - Mutation

    @discardableResult
    mutating func add(_ item: ClipboardItem, maxSize: Int) -> AddOutcome {
        var stored = item
        var wasDuplicate = false

        // An existing entry supersedes the new one when it already carries every
        // non-transient representation. Re-copying the same thing bumps the counter
        // and moves it to the top instead of creating a second row.
        if let index = items.firstIndex(where: { $0.supersedes(item) }) {
            let existing = items.remove(at: index)
            stored.firstCopiedAt = existing.firstCopiedAt
            stored.numberOfCopies = existing.numberOfCopies + 1
            stored.pin = existing.pin
            // Keep the original app attribution when the re-copy has none.
            stored.appBundleID = item.appBundleID ?? existing.appBundleID
            wasDuplicate = true
        }

        items.insert(stored, at: 0)
        let evicted = enforceLimit(maxSize)
        return AddOutcome(stored: stored, wasDuplicate: wasDuplicate, evicted: evicted)
    }

    /// Drops the oldest unpinned entries past `maxSize`. Pinned entries never count
    /// toward the limit and are never evicted.
    @discardableResult
    mutating func enforceLimit(_ maxSize: Int) -> [ClipboardItem] {
        guard maxSize > 0 else { return [] }

        var seenUnpinned = 0
        var evicted: [ClipboardItem] = []
        items.removeAll { item in
            guard !item.isPinned else { return false }
            seenUnpinned += 1
            guard seenUnpinned > maxSize else { return false }
            evicted.append(item)
            return true
        }
        return evicted
    }

    @discardableResult
    mutating func remove(id: UUID) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    /// Toggles the pin, assigning an unused quick-select character when pinning.
    @discardableResult
    mutating func togglePin(id: UUID) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        if items[index].isPinned {
            items[index].pin = nil
        } else {
            items[index].pin = nextAvailablePin()
        }
        return items[index]
    }

    /// Removes everything unpinned, returning the removed entries so their blobs can go too.
    @discardableResult
    mutating func clearUnpinned() -> [ClipboardItem] {
        let removed = unpinned
        items.removeAll { !$0.isPinned }
        return removed
    }

    @discardableResult
    mutating func clearAll() -> [ClipboardItem] {
        let removed = items
        items.removeAll()
        return removed
    }

    // MARK: - Pins

    /// Characters offered as pin shortcuts. Excludes letters bound to common actions
    /// elsewhere in the panel so a pin can never shadow them.
    static let availablePins: [String] = "bcdefghijklmnorstuxy".map(String.init)

    private func nextAvailablePin() -> String? {
        let taken = Set(items.compactMap(\.pin))
        return Self.availablePins.first { !taken.contains($0) }
    }
}
