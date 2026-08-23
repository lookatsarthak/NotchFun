//
//  ShelfStateViewModel.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-09.

import Foundation
import AppKit

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { ShelfPersistenceService.shared.save(items) }
    }

    @Published var isLoading: Bool = false

    /// Why the last drop added nothing, shown briefly in the shelf.
    ///
    /// A drop that resolves to no items used to be indistinguishable from a drop that
    /// never registered, which is exactly how a real bug went unnoticed: the item was
    /// discarded and nothing was written anywhere.
    @Published var lastDropError: String?

    var isEmpty: Bool { items.isEmpty }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: Data] = [:]
    private var updateTask: Task<Void, Never>?

    private init() {
        // nil means the file exists but could not be read. We still have to start from
        // something, and the two safety nets that now sit under this - the preserved
        // `items.unreadable-*.json` copy and the rolling `items.previous.json` - are what
        // make starting empty recoverable rather than final.
        items = ShelfPersistenceService.shared.load() ?? []
    }


    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        var merged = items
        // Deduplicate by identityKey while preserving order (existing first)
        var seen: Set<String> = Set(merged.map { $0.identityKey })
        for it in newItems {
            let key = it.identityKey
            if !seen.contains(key) {
                merged.append(it)
                seen.insert(key)
            }
        }
        items = merged
    }

    func remove(_ item: ShelfItem) {
        item.cleanupStoredData()
        items.removeAll { $0.id == item.id }
    }

    /// Empties the shelf.
    ///
    /// `cleanupStoredData` runs per item, which matters for the ones the shelf made
    /// itself - dropped text and images live in temporary files that would otherwise be
    /// left behind. Files you dropped in are only ever referenced by bookmark, so
    /// clearing the shelf never touches the originals on disk.
    func clearAll() {
        for item in items { item.cleanupStoredData() }
        items.removeAll()
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if case .file = items[idx].kind {
            items[idx].kind = .file(bookmark: bookmark)
        }
    }

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data) {
        pendingBookmarkUpdates[item.id] = bookmark
        
        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            
            guard let self = self else { return }
            
            for (itemID, bookmarkData) in self.pendingBookmarkUpdates {
                if let idx = self.items.firstIndex(where: { $0.id == itemID }),
                   case .file = self.items[idx].kind {
                    self.items[idx].kind = .file(bookmark: bookmarkData)
                }
            }
            
            self.pendingBookmarkUpdates.removeAll()
        }
    }


    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            ShelfDropService.lastFailureReason = nil
            let dropped = await ShelfDropService.items(from: providers)
            await MainActor.run {
                self?.add(dropped)
                self?.isLoading = false
                if dropped.isEmpty {
                    self?.reportDropFailure(ShelfDropService.lastFailureReason)
                }
            }
        }
    }

    /// Shows why a drop produced nothing, then clears it again.
    private func reportDropFailure(_ reason: String?) {
        lastDropError = reason ?? "That item could not be added to the shelf."
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                if self?.lastDropError == (reason ?? "That item could not be added to the shelf.") {
                    self?.lastDropError = nil
                }
            }
        }
    }

    /// Drops shelf entries whose file has actually been deleted.
    ///
    /// Runs whenever the shelf appears, and used to drop anything whose bookmark failed
    /// to *resolve* - which is a different and much broader condition than the file being
    /// gone. Security-scoped bookmarks are bound to the signing identity of the app that
    /// created them, so a change of identity makes every bookmark unresolvable at once
    /// while every file is still on disk. Opening the shelf tab once was then enough to
    /// erase the whole shelf and delete the backing files for anything the shelf had
    /// made itself, with no warning and nothing to undo it.
    ///
    /// So an entry is only removed on positive evidence that the file is gone. If we
    /// cannot resolve the bookmark we keep the entry: leaving a row the user has to
    /// remove by hand is a trivial annoyance next to deleting their shelf.
    func cleanupInvalidItems() {
        Task { [weak self] in
            guard let self else { return }
            var keep: [ShelfItem] = []
            var unresolvable = 0
            for item in self.items {
                switch item.kind {
                case .file(let data):
                    switch await Bookmark(data: data).status() {
                    case .available:
                        keep.append(item)
                    case .unresolvable:
                        unresolvable += 1
                        keep.append(item)
                    case .fileMissing:
                        item.cleanupStoredData()
                    }
                default:
                    keep.append(item)
                }
            }
            if unresolvable > 0 {
                NSLog("Shelf: kept \(unresolvable) item(s) whose bookmark could not be resolved")
            }
            let result = keep
            await MainActor.run { self.items = result }
        }
    }


    func resolveFileURL(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            scheduleDeferredBookmarkUpdate(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            updateBookmark(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveFileURLs(for items: [ShelfItem]) -> [URL] {
        var urls: [URL] = []
        for it in items {
            if let u = resolveFileURL(for: it) { urls.append(u) }
        }
        return urls
    }
}
