//
//  TransientDropLocationTests.swift
//  boringNotchTests
//

import Foundation
import Testing

/// Which dropped files the shelf copies (their sender deletes them) and which it only
/// points at. Getting this wrong one way loses screenshots dragged from their thumbnail;
/// the other way duplicates every file someone parks on the shelf.
@Suite("Transient drop locations")
struct TransientDropLocationTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("A screenshot thumbnail's file is transient (the bug this guards)")
    func screenshotThumbnail() {
        // The exact shape screencaptureui used when this was reproduced on macOS 27.
        #expect(url("/var/folders/6m/n4gr8_011f9dvxmrsf6svh200000gn/T/TemporaryItems/NSIRD_screencaptureui_ghnW1Z/Screenshot 2026-10-07 at 1.36.01 PM.png").isTransientDropLocation)
        #expect(url("/private/var/folders/6m/n4gr8_011f9dvxmrsf6svh200000gn/T/TemporaryItems/NSIRD_screencaptureui_ghnW1Z/Screenshot.png").isTransientDropLocation)
    }

    @Test("SwiftUI's promise folder, temporary and cache folders, and /tmp are transient")
    func temporaryPlaces() {
        #expect(url("/Users/someone/Library/Containers/io.github.lookatsarthak.notchfun/Data/Library/Caches/com.apple.SwiftUI.filePromises-248A139D/Photo.png").isTransientDropLocation)
        #expect(url("/var/folders/ab/cdef/T/some-app/attachment.pdf").isTransientDropLocation)
        #expect(url("/var/folders/ab/cdef/C/com.example.app/thing.zip").isTransientDropLocation)
        #expect(url("/tmp/export.csv").isTransientDropLocation)
        #expect(url("/private/tmp/export.csv").isTransientDropLocation)
        #expect(url(NSTemporaryDirectory()).appendingPathComponent("x/y.txt").isTransientDropLocation)
        #expect(url("/Users/someone/Library/Containers/com.apple.mail/Data/tmp/TemporaryItems/Mail/invoice.pdf").isTransientDropLocation)
    }

    @Test("Ordinary files are referenced, not copied")
    func ordinaryFiles() {
        #expect(!url("/Users/someone/Desktop/Screenshot 2026-10-07 at 1.36.01 PM.png").isTransientDropLocation)
        #expect(!url("/Users/someone/Documents/Report.pdf").isTransientDropLocation)
        #expect(!url("/Users/someone/Downloads/NotchFun.dmg").isTransientDropLocation)
        #expect(!url("/Volumes/External/Footage/clip.mov").isTransientDropLocation)
        #expect(!url("/Applications/NotchFun.app").isTransientDropLocation)
        // A folder merely named like a temporary one is not.
        #expect(!url("/Users/someone/T/notes.txt").isTransientDropLocation)
        #expect(!url("/var/folders").isTransientDropLocation)
        #expect(!url("/tmpfiles/report.txt").isTransientDropLocation)
    }

    @Test("Web links are never transient files")
    func webLinks() {
        #expect(!URL(string: "https://example.com/tmp/file.png")!.isTransientDropLocation)
    }
}
