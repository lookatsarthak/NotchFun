//
//  ShelfDropService.swift
//  boringNotch
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
        
        if let loaded = await provider.loadData() {
            if let tempDataURL = await TemporaryFileStorageService.shared.createTempFile(
                for: .data(loaded.data, suggestedName: loaded.suggestedName ?? provider.suggestedName)),
               let bookmark = createBookmark(for: tempDataURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true)
            }
            return nil
        }
        
        if let fileURL = await provider.extractItem() {
            if let bookmark = createBookmark(for: fileURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
        }
        
        return nil
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

