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

    /// Reads the history back, or returns `nil` if there is a file we could not use.
    ///
    /// The nil case is load-bearing. This used to return `[]` for "nothing saved", "could
    /// not read it", "schema is from a newer build" and "root JSON is the wrong shape"
    /// alike — and the caller answers an empty result by pruning every blob on disk and
    /// then writing the empty history back. So a transient read error, or one launch of a
    /// newer build followed by a downgrade, silently destroyed the entire history *and*
    /// its payloads. The guard written to protect the data was the surest way to lose it.
    ///
    /// Same treatment ShelfPersistenceService got, for the same reason.
    func load() -> [ClipboardItem]? {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        guard let data = try? Data(contentsOf: indexURL) else {
            Self.logger.error("Clipboard index exists but could not be read; leaving it alone")
            return nil
        }
        let decoder = Self.makeDecoder()

        if let index = try? decoder.decode(Index.self, from: data) {
            guard index.schemaVersion <= Self.currentSchemaVersion else {
                Self.logger.error("Clipboard index schema \(index.schemaVersion, privacy: .public) is newer than supported; leaving it alone")
                return nil
            }
            return index.items
        }

        // Whole-file decode failed. Salvage what we can rather than losing the history
        // to one corrupt record.
        return salvageItems(from: data, decoder: decoder)
    }

    private func salvageItems(from data: Data, decoder: JSONDecoder) -> [ClipboardItem]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = root["items"] as? [Any] else {
            Self.logger.error("Clipboard index is not readable JSON; leaving it alone")
            preserveUnreadableIndex(reason: "not readable JSON")
            return nil
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

        if failed > 0 {
            Self.logger.warning("Recovered \(items.count, privacy: .public) clipboard items, discarded \(failed, privacy: .public) corrupted")
            // The discarded records' blobs are about to be pruned and the file rewritten
            // with the remainder, so this copy is the only way back to them.
            preserveUnreadableIndex(reason: "\(failed) undecodable item(s)")
        }
        return items
    }

    /// Copies the index aside so a bad read stays recoverable by hand.
    private func preserveUnreadableIndex(reason: String) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let copy = indexURL.deletingLastPathComponent()
            .appendingPathComponent("index.unreadable-\(stamp).json")
        try? FileManager.default.copyItem(at: indexURL, to: copy)
        Self.logger.warning("Preserved unreadable clipboard index as \(copy.lastPathComponent, privacy: .public) (\(reason, privacy: .public))")
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
