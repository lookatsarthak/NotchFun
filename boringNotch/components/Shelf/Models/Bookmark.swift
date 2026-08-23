//
//  Bookmark.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-08.
//

import Foundation
import AppKit

struct Bookmark: Sendable, Equatable, Codable {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(url: URL) throws {
        guard url.isFileURL else {
            throw NSError(domain: "Bookmark", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Not a file URL: \(url.absoluteString)"
            ])
        }

        // Access has to be started before anything touches the file, including the
        // existence check below.
        //
        // A file dropped onto the shelf arrives with a sandbox extension attached to
        // this URL. Nothing here used to consume it - this was the one place in the
        // app that used a security-scoped URL without starting access - so both
        // `fileExists` and `bookmarkData` were asking about a file the sandbox would
        // not let us see. `fileExists` then returns false for a file that is plainly
        // there, and the item is discarded before `bookmarkData` is even reached.
        // Whether that happened came down to timing, which is why drops failed
        // intermittently rather than always.
        self.data = try url.accessSecurityScopedResource { url -> Data in
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw NSError(domain: "Bookmark", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No file at \(url.path), or it is not readable from the sandbox"
                ])
            }
            do {
                return try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                NSLog("Bookmark: could not create one for \(url.path): \(error)")
                throw error
            }
        }
    }

    func resolve() -> (url: URL?, refreshedData: Data?) {
        guard !data.isEmpty else { return (nil, nil) }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale, let newData = try? url.bookmarkData(options: [.withSecurityScope]) {
                NSLog("⚠️ Bookmark was stale for \(url.path), refreshed")
                return (url, newData)
            }
            return (url, nil)
        } catch {
            NSLog("❌ Failed to resolve bookmark: \(error.localizedDescription)")
            return (nil, nil)
        }
    }

    func resolveURL() -> URL? {
        return resolve().url
    }

    var refreshedData: Data? {
        return resolve().refreshedData
    }
    
    static func update(in items: inout [ShelfItem], for item: ShelfItem, newBookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard case .file = items[idx].kind else { return }
        items[idx].kind = ShelfItemKind.file(bookmark: newBookmark)
    }

    /// What we can actually say about the file behind this bookmark.
    ///
    /// The distinction between the last two cases is the whole point. A bookmark that
    /// cannot be resolved is not evidence that the file is gone - it is evidence that
    /// *we* cannot see it. Security-scoped bookmarks are tied to the code signature of
    /// the app that created them, so a change of signing identity makes every bookmark
    /// in the shelf unresolvable while every file is still sitting exactly where it was.
    enum Status: Sendable, Equatable {
        /// Resolved, and the file is there.
        case available
        /// Resolved to a path with nothing at it. The file really is gone.
        case fileMissing
        /// Could not be resolved at all. Says nothing about the file.
        case unresolvable
    }

    func status() async -> Status {
        let (url, _) = resolve()
        guard let url else { return .unresolvable }

        // Deliberately not `accessSecurityScopedResource`: that helper throws away
        // whether access actually started and runs its body regardless. This app is
        // sandboxed, so a refused extension makes `fileExists` answer false for a file
        // that is plainly there - and false, here, is the verdict that deletes it. The
        // first version of this fix went through that helper and so never delivered the
        // guarantee it was written for.
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        if FileManager.default.fileExists(atPath: url.path) { return .available }

        // Absence only means something if we were actually allowed to look. `started`
        // is also false for a bookmark that never needed a scope, which is why this
        // checks existence first rather than bailing on `!started`.
        return started ? .fileMissing : .unresolvable
    }

    func validate() async -> Bool {
        await status() == .available
    }

    func withAccess<T: Sendable>(_ block: @Sendable (URL) async throws -> T) async rethrows -> T? {
        let url = resolveURL()
        guard let url = url else { return nil }
        return try await url.accessSecurityScopedResource { url in
            try await block(url)
        }
    }

    func withAccess<T>(_ block: (URL) throws -> T) rethrows -> T? {
        let url = resolveURL()
        guard let url = url else { return nil }
        return try url.accessSecurityScopedResource { url in
            try block(url)
        }
    }
}
