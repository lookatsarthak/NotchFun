//
//  ClipboardPasteboardWriter.swift
//  boringNotch
//

import AppKit
import Foundation

/// Puts a history entry back on a pasteboard.
///
/// Split out of the view model so the write can be exercised against a scratch
/// `NSPasteboard` in isolation — this is the step where a mistake silently costs the
/// user the thing they just clicked.
enum ClipboardPasteboardWriter {

    /// Writes only the plain text of an item, dropping fonts, colours and links.
    ///
    /// Returns false when the entry has no text at all - an image has no plain form, and
    /// pasting nothing would be worse than doing nothing.
    @discardableResult
    static func writePlainText(
        _ item: ClipboardItem,
        to pasteboard: NSPasteboard = .general,
        blobStore: ClipboardBlobStore,
        cleanLinks: Bool = false
    ) -> Bool {
        guard let text = plainText(of: item, blobStore: blobStore), !text.isEmpty else { return false }
        let resolved = cleanLinks ? (URLCleaner.clean(text)?.cleaned ?? text) : text
        pasteboard.clearContents()
        pasteboard.setString(resolved, forType: .string)
        pasteboard.setData(Data(), forType: .fromNotchFun)
        return true
    }

    /// The item's text, preferring a real string payload and falling back to the title.
    static func plainText(of item: ClipboardItem, blobStore: ClipboardBlobStore) -> String? {
        stringPayload(of: item, blobStore: blobStore) ?? (item.title.isEmpty ? nil : item.title)
    }

    /// The item's actual `public.utf8-plain-text` payload, with no title fallback.
    ///
    /// Link cleaning uses this rather than `plainText`: the title is a display string
    /// that has been truncated and stripped of newlines, so rewriting a pasteboard from
    /// it would mean pasting something the user never copied.
    static func stringPayload(of item: ClipboardItem, blobStore: ClipboardBlobStore) -> String? {
        for ref in item.contents where ref.type == NSPasteboard.PasteboardType.string.rawValue {
            if let data = blobStore.data(for: ref), let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        return nil
    }

    /// - Returns: `true` if something was actually written.
    @discardableResult
    static func write(
        _ item: ClipboardItem,
        to pasteboard: NSPasteboard,
        blobStore: ClipboardBlobStore,
        cleanLinks: Bool = false
    ) -> Bool {
        // A link that cleans is written as plain text and nothing else.
        //
        // Browsers put a URL on the pasteboard three or four ways at once - plain text,
        // public.url, and an HTML anchor. Cleaning only the plain text would leave the
        // tracker in the copies an app might prefer, so a half-cleaned pasteboard is
        // worse than none: the setting would appear to work and sometimes not. A bare
        // URL carries no formatting worth preserving, so dropping the other
        // representations costs nothing.
        if cleanLinks,
           let text = stringPayload(of: item, blobStore: blobStore),
           let cleaned = URLCleaner.clean(text) {
            pasteboard.clearContents()
            pasteboard.setString(cleaned.cleaned, forType: .string)
            pasteboard.setData(Data(), forType: .fromNotchFun)
            if let bundleID = item.appBundleID {
                pasteboard.setString(bundleID, forType: .source)
            }
            return true
        }

        // Collect everything first, so a failure to resolve content leaves the existing
        // pasteboard untouched instead of clearing it and writing nothing.
        let fileURLs = item.fileURLs(using: blobStore)

        let element = NSPasteboardItem()
        var wroteContent = false
        for ref in item.contents where ref.pasteboardType != .fileURL {
            guard let data = blobStore.data(for: ref), !data.isEmpty else { continue }
            element.setData(data, forType: ref.pasteboardType)
            wroteContent = true
        }

        guard wroteContent || !fileURLs.isEmpty else { return false }

        // Marks the write as ours so the monitor does not record it as a new copy.
        element.setString("", forType: .fromNotchFun)
        if let bundleID = item.appBundleID {
            element.setString(bundleID, forType: .source)
        }

        var objects: [NSPasteboardWriting] = []
        // File URLs go through writeObjects; also writing their raw data makes some
        // apps paste the item twice.
        objects.append(contentsOf: fileURLs as [NSPasteboardWriting])
        if wroteContent { objects.append(element) }

        pasteboard.clearContents()
        return pasteboard.writeObjects(objects)
    }
}
