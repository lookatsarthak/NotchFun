//
//  ShelfDropService.swift
//  NotchFun
//
//  Created by Alexander on 2025-09-26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfDropService {
    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] {
        var results: [ShelfItem] = []

        for provider in providers {
            if let item = await processProvider(provider) {
                results.append(item)
            }
        }

        return results
    }
    
    private static func processProvider(_ provider: NSItemProvider) async -> ShelfItem? {
        if let actualFileURL = await provider.extractFileURL() {
            if actualFileURL.isTransientDropLocation { return await keepCopy(of: actualFileURL) }
            if let bookmark = createBookmark(for: actualFileURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
            return nil
        }
        
        if let url = await provider.extractURL() {
            if url.isFileURL {
                if let bookmark = createBookmark(for: url) {
                    return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
                }
            } else {
                return await ShelfItem(kind: .link(url: url), isTemporary: false)
            }
            return nil
        }
        
        if let text = await provider.extractText() {
            return await ShelfItem(kind: .text(string: text), isTemporary: false)
        }
        
        switch await provider.loadData() {
        case .bytes(let data):
            if let tempDataURL = await TemporaryFileStorageService.shared.createTempFile(
                for: .data(data, suggestedName: provider.suggestedName)),
               let bookmark = createBookmark(for: tempDataURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true)
            }
            return nil
        case .promisedFile(let url):
            let item = await keepCopy(of: url)
            removeSwiftUIPromise(at: url)
            return item
        case nil:
            break
        }
        
        if let fileURL = await provider.extractItem() {
            if fileURL.isTransientDropLocation { return await keepCopy(of: fileURL) }
            if let bookmark = createBookmark(for: fileURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
        }
        
        return nil
    }
    
    /// A file its sender is about to delete (see `URL.isTransientDropLocation`): the shelf
    /// keeps its own copy, removed again with the entry, rather than a bookmark to a file
    /// that is gone a few seconds later.
    private static func keepCopy(of url: URL) async -> ShelfItem? {
        guard let copy = await TemporaryFileStorageService.shared.createTempFile(for: .copy(url)) else {
            lastFailureReason = "\(url.lastPathComponent) could not be copied to the shelf."
            return nil
        }
        guard let bookmark = createBookmark(for: copy) else { return nil }
        return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true)
    }

    /// SwiftUI receives promises into a folder inside NotchFun's own container, which is
    /// ours to tidy once the copy is made. Anyone else's temporary folder is left alone.
    private static func removeSwiftUIPromise(at url: URL) {
        guard url.path.contains("/com.apple.SwiftUI.filePromises") else { return }
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: url)
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// `try?` here is what made a failed drop indistinguishable from no drop at all:
    /// the item was discarded and nothing was written anywhere. The reason is now
    /// logged, and reported so the shelf can say something rather than silently
    /// ignoring the file.
    private static func createBookmark(for url: URL) -> Data? {
        do {
            return try Bookmark(url: url).data
        } catch {
            NSLog("Shelf: dropped file could not be added - \(url.lastPathComponent): \(error.localizedDescription)")
            lastFailureReason = error.localizedDescription
            return nil
        }
    }

    /// Why the most recent drop produced nothing, for the view to surface.
    nonisolated(unsafe) static var lastFailureReason: String?
}

