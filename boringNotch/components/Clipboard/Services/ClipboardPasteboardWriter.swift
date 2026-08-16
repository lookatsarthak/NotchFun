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

    /// - Returns: `true` if something was actually written.
    @discardableResult
    static func write(
        _ item: ClipboardItem,
        to pasteboard: NSPasteboard,
        blobStore: ClipboardBlobStore
    ) -> Bool {
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
