//
//  URL+TransientDropLocation.swift
//  NotchFun
//

import Foundation

extension URL {
    /// Whether a dropped file lives somewhere its sender will clean up shortly, so the shelf
    /// has to keep its own copy rather than point at it.
    ///
    /// A file promise (a screenshot's floating thumbnail, a Mail attachment, an image dragged
    /// out of a browser) is written to a temporary folder for the drop. macOS used to deliver
    /// promises into SwiftUI's own `com.apple.SwiftUI.filePromises` folder; it now hands over
    /// the sender's copy instead, and screencaptureui writes its thumbnail to
    /// `…/T/TemporaryItems/NSIRD_screencaptureui_…/` and deletes it about five seconds after
    /// the drag. A shelf entry that only pointed at that file lost it moments later, which is
    /// how screenshot thumbnails "opened the shelf but didn't stay".
    ///
    /// Ordinary files (Desktop, Documents, Downloads, other volumes) are not transient: the
    /// shelf keeps referring to those rather than duplicating them.
    var isTransientDropLocation: Bool {
        guard isFileURL else { return false }
        let path = Self.canonicalPath(path)
        if path.contains("/com.apple.SwiftUI.filePromises") || path.contains("/TemporaryItems/") { return true }
        for root in Self.temporaryRoots where path == root || path.hasPrefix(root + "/") { return true }
        // Any user's per-user temporary or cache folder: /private/var/folders/xx/yyyy/T|C/…
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count > 5, parts[0] == "private", parts[1] == "var", parts[2] == "folders", parts[5] == "T" || parts[5] == "C" {
            return true
        }
        return false
    }

    /// /tmp and /var are symlinks into /private; compare everything in its /private form.
    private static func canonicalPath(_ path: String) -> String {
        for (link, target) in [("/tmp", "/private/tmp"), ("/var", "/private/var")] where path == link || path.hasPrefix(link + "/") {
            return target + path.dropFirst(link.count)
        }
        return path
    }

    private static let temporaryRoots: [String] = {
        var roots = ["/private/tmp"]
        let ours = canonicalPath(URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path)
        roots.append(ours.hasSuffix("/") ? String(ours.dropLast()) : ours)
        return roots
    }()
}
