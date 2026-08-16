//
//  ClipboardPersistenceService.swift
//  boringNotch
//
//  Follows the pattern of ShelfPersistenceService, with two differences: writes are
//  debounced and performed off the main actor (clipboard history changes far more
//  often than the shelf does), and the file carries a schema version.
//

import Foundation
import os

@MainActor
final class ClipboardPersistenceService {
    static let shared = ClipboardPersistenceService()

    nonisolated private static let logger = Logger(subsystem: "io.github.lookatsarthak.notchfun", category: "ClipboardPersistence")

    /// Bump when the on-disk shape changes incompatibly.
    nonisolated static let currentSchemaVersion = 1

    /// How long to coalesce rapid mutations before hitting the disk.
    nonisolated private static let writeDebounce: Duration = .milliseconds(500)

    private let indexURL: URL
    private let blobStore: ClipboardBlobStore
    private var pendingWrite: Task<Void, Never>?

    init(blobStore: ClipboardBlobStore = .shared) {
        self.blobStore = blobStore
        self.indexURL = blobStore.directory.appendingPathComponent("index.json")
    }

    private struct Index: Codable {
        var schemaVersion: Int
        var items: [ClipboardItem]
    }

    nonisolated private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    nonisolated private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Load

    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = Self.makeDecoder()

        if let index = try? decoder.decode(Index.self, from: data) {
            guard index.schemaVersion <= Self.currentSchemaVersion else {
                Self.logger.error("Clipboard index schema \(index.schemaVersion, privacy: .public) is newer than supported; ignoring")
                return []
            }
            return index.items
        }

        // Whole-file decode failed. Salvage what we can rather than losing the history
        // to one corrupt record — same approach as ShelfPersistenceService.load().
        return salvageItems(from: data, decoder: decoder)
    }

    private func salvageItems(from data: Data, decoder: JSONDecoder) -> [ClipboardItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = root["items"] as? [Any] else {
            Self.logger.error("Clipboard index is not readable JSON; starting empty")
            return []
        }

        var items: [ClipboardItem] = []
        var failed = 0
        for raw in rawItems {
            guard let itemData = try? JSONSerialization.data(withJSONObject: raw),
                  let item = try? decoder.decode(ClipboardItem.self, from: itemData) else {
                failed += 1
                continue
            }
            items.append(item)
        }

        Self.logger.warning("Recovered \(items.count, privacy: .public) clipboard items, discarded \(failed, privacy: .public) corrupted")
        return items
    }

    // MARK: - Save

    /// Coalesces rapid mutations into one atomic write on a background task.
    func scheduleSave(_ items: [ClipboardItem]) {
        pendingWrite?.cancel()
        let url = indexURL
        pendingWrite = Task { [items] in
            try? await Task.sleep(for: Self.writeDebounce)
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) { Self.write(items, to: url) }.value
        }
    }

    /// Writes immediately, bypassing the debounce.
    func flush(_ items: [ClipboardItem]) async {
        pendingWrite?.cancel()
        pendingWrite = nil
        let target = indexURL
        await Task.detached(priority: .utility) { Self.write(items, to: target) }.value
    }

    /// Blocking flush for `applicationWillTerminate`, which cannot await — a debounced
    /// write would otherwise be lost when the process exits.
    func flushSynchronously(_ items: [ClipboardItem]) {
        pendingWrite?.cancel()
        pendingWrite = nil
        Self.write(items, to: indexURL)
    }

    nonisolated private static func write(_ items: [ClipboardItem], to url: URL) {
        do {
            let data = try makeEncoder().encode(Index(schemaVersion: currentSchemaVersion, items: items))
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            logger.error("Failed to save clipboard index: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Cleanup

    func deleteEverything() {
        pendingWrite?.cancel()
        pendingWrite = nil
        try? FileManager.default.removeItem(at: indexURL)
        blobStore.deleteAll()
    }
}
