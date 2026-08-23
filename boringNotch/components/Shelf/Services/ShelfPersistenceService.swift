//
//  ShelfPersistenceService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import Foundation

// Access model types
@_exported import struct Foundation.URL


final class ShelfPersistenceService {
    static let shared = ShelfPersistenceService()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (support ?? fm.temporaryDirectory).appendingPathComponent("NotchFun", isDirectory: true).appendingPathComponent("Shelf", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("items.json")
        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    /// Reads the shelf back, or returns `nil` if the file exists but could not be read.
    ///
    /// The nil case matters more than it looks. This used to return `[]` for both "there
    /// is nothing saved" and "I could not read what was saved", and since `items` writes
    /// itself back on every change, one unreadable read was enough to overwrite the real
    /// file with an empty array and destroy the shelf permanently. An empty shelf and an
    /// unreadable shelf must never be the same value.
    func load() -> [ShelfItem]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        guard let data = try? Data(contentsOf: fileURL) else {
            NSLog("Shelf: items.json exists but could not be read; leaving it alone")
            preserveUnreadableFile(reason: "unreadable")
            return nil
        }

        if let items = try? decoder.decode([ShelfItem].self, from: data) {
            return items
        }

        // Decode per item, so one bad entry costs one entry rather than the shelf.
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            preserveUnreadableFile(reason: "not a JSON array")
            return nil
        }

        var validItems: [ShelfItem] = []
        var failed = 0
        for jsonItem in jsonArray {
            guard let itemData = try? JSONSerialization.data(withJSONObject: jsonItem),
                  let item = try? decoder.decode(ShelfItem.self, from: itemData)
            else { failed += 1; continue }
            validItems.append(item)
        }

        if failed > 0 {
            NSLog("Shelf: loaded \(validItems.count) item(s), \(failed) could not be decoded")
            // Keep a copy before the good items get written back over the bad file.
            preserveUnreadableFile(reason: "\(failed) undecodable item(s)")
        }
        return validItems
    }

    /// Copies the current file aside so a bad read is recoverable by hand.
    private func preserveUnreadableFile(reason: String) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let copy = fileURL.deletingLastPathComponent()
            .appendingPathComponent("items.unreadable-\(stamp).json")
        try? FileManager.default.copyItem(at: fileURL, to: copy)
        NSLog("Shelf: preserved unreadable items.json as \(copy.lastPathComponent) (\(reason))")
    }

    func save(_ items: [ShelfItem]) {
        do {
            let data = try encoder.encode(items)
            // Keep the previous contents one step back. Clearing the shelf is a single
            // click, and until now there was nothing behind it.
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("items.previous.json")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
            try data.write(to: fileURL, options: Data.WritingOptions.atomic)
        } catch {
            NSLog("Shelf: failed to save items: \(error.localizedDescription)")
        }
    }
}
