//
//  ClipboardToShelf.swift
//  NotchFun
//

import AppKit

/// Puts a clipboard entry on the shelf, so it can be dragged into another app later.
///
/// Each kind becomes what the shelf would have made of it had it been dropped there:
/// text stays text, a link stays a link, an image becomes a PNG file the shelf owns and
/// deletes when it's removed, and copied files are referenced where they are.
@MainActor
enum ClipboardToShelf {

    /// Adds the entry and returns true, or sets the shelf's message and returns false.
    @discardableResult
    static func add(_ item: ClipboardItem, from clipboard: ClipboardStateViewModel) async -> Bool {
        let shelf = ShelfStateViewModel.shared
        let items = await shelfItems(for: item, from: clipboard)
        guard !items.isEmpty else {
            shelf.lastDropError = item.kind == .files
                ? "Couldn't add the copied file. Drag it from Finder onto the shelf instead."
                : "Couldn't add that to the shelf."
            return false
        }
        shelf.lastDropError = nil
        shelf.add(items)
        return true
    }

    private static func shelfItems(for item: ClipboardItem, from clipboard: ClipboardStateViewModel) async -> [ShelfItem] {
        switch item.kind {
        case .files:
            // A copied file comes with no sandbox access of its own, so this works for
            // files NotchFun can already read and fails cleanly for the rest.
            return clipboard.fileURLs(of: item).compactMap { url in
                (try? Bookmark(url: url)).map { ShelfItem(kind: .file(bookmark: $0.data)) }
            }
        case .link:
            let text = (clipboard.text(of: item) ?? item.title).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: text), url.scheme != nil {
                return [ShelfItem(kind: .link(url: url))]
            }
            return [ShelfItem(kind: .text(string: text))]
        case .text:
            guard let text = clipboard.text(of: item), !text.isEmpty else { return [] }
            return [ShelfItem(kind: .text(string: text))]
        case .image:
            guard let data = clipboard.imageData(of: item), let png = pngData(data),
                  let url = await TemporaryFileStorageService.shared.createTempFile(
                      for: .data(png, suggestedName: "Clipboard Image.png")),
                  let bookmark = try? Bookmark(url: url)
            else { return [] }
            return [ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: true)]
        }
    }

    /// Clipboard images are usually TIFF. A PNG is what any app will take from a drag.
    private static func pngData(_ data: Data) -> Data? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return data }
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
