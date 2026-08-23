//
//  ClipboardKeyAndSearchTests.swift
//  boringNotchTests
//

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@Suite("Clipboard key interpretation")
struct ClipboardKeyInterpreterTests {
    private func interpret(_ code: Int, _ flags: CGEventFlags = [], text: String? = nil) -> ClipboardKeyEvent? {
        ClipboardKeyInterpreter.interpret(keyCode: CGKeyCode(code), flags: flags, text: text)
    }

    @Test("Command shortcuts still reach the system")
    func commandCombosPassThrough() {
        // While the panel has a key tap installed it sees everything, so anything it
        // does not itself use must pass through - otherwise the user is trapped in it
        // and cannot even quit or switch apps.
        #expect(interpret(kVK_ANSI_Q, .maskCommand) == nil)
        #expect(interpret(kVK_Tab, .maskCommand) == nil)
        #expect(interpret(kVK_ANSI_W, .maskCommand) == nil)
        #expect(interpret(kVK_Space, .maskCommand) == nil)
        #expect(interpret(kVK_ANSI_V, .maskCommand) == nil)
        #expect(interpret(kVK_ANSI_C, [.maskCommand, .maskShift]) == nil)
    }

    @Test("Command plus a digit picks that entry")
    func quickSelect() {
        #expect(interpret(kVK_ANSI_1, .maskCommand) == .quickSelect(1))
        #expect(interpret(kVK_ANSI_9, .maskCommand) == .quickSelect(9))
        // Adding another modifier makes it someone else's shortcut again.
        #expect(interpret(kVK_ANSI_1, [.maskCommand, .maskAlternate]) == nil)
    }

    @Test("Navigation and editing keys map to actions")
    func navigation() {
        #expect(interpret(kVK_Return) == .confirm)
        #expect(interpret(kVK_ANSI_KeypadEnter) == .confirm)
        // Option-Return pastes without formatting. This shipped unreachable: the guard
        // that passes option combos through to the app underneath sat above the case
        // that handles Return, so it swallowed this one too.
        #expect(interpret(kVK_Return, .maskAlternate) == .confirmAsPlainText)
        #expect(interpret(kVK_ANSI_KeypadEnter, .maskAlternate) == .confirmAsPlainText)
        #expect(interpret(kVK_Escape) == .cancel)
        #expect(interpret(kVK_Delete) == .backspace)
        #expect(interpret(kVK_UpArrow) == .moveUp)
        #expect(interpret(kVK_DownArrow) == .moveDown)
        #expect(interpret(kVK_Home) == .moveToTop)
        #expect(interpret(kVK_PageDown) == .pageDown)
        #expect(interpret(kVK_LeftArrow) == nil)
        #expect(interpret(kVK_Tab) == nil)
    }

    @Test("Readline-style control keys work, others pass through")
    func controlBindings() {
        #expect(interpret(kVK_ANSI_U, .maskControl) == .clearSearch)
        #expect(interpret(kVK_ANSI_W, .maskControl) == .deleteWord)
        #expect(interpret(kVK_ANSI_N, .maskControl) == .moveDown)
        #expect(interpret(kVK_ANSI_X, .maskControl) == nil)
    }

    @Test("Typing searches, including non-Latin input")
    func typing() {
        #expect(interpret(kVK_ANSI_A, [], text: "a") == .character("a"))
        #expect(interpret(kVK_ANSI_A, .maskShift, text: "A") == .character("A"))
        #expect(interpret(kVK_ANSI_A, [], text: "ж") == .character("ж"))
        // Option combos belong to the app underneath, and control characters are not text.
        #expect(interpret(kVK_ANSI_A, .maskAlternate, text: "å") == nil)
        #expect(interpret(kVK_ANSI_A, [], text: "\u{1}") == nil)
        #expect(interpret(kVK_ANSI_A, [], text: nil) == nil)
    }
}

@Suite("Clipboard search")
struct ClipboardSearchTests
{
    private func makeCorpus(_ store: ClipboardBlobStore) -> [ClipboardItem] {
        ["boring.notch release notes", "Hello World", "café menu", "https://apple.com"].map { title in
            ClipboardItem(
                contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                         data: Data(title.utf8))],
                title: title, kind: .text
            )
        }
    }

    @Test("An empty query shows the whole history")
    func emptyQuery() {
        let directory = makeTemporaryDirectory("search-empty")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        #expect(ClipboardSearchService.search("", in: makeCorpus(store)).count == 4)
    }

    @Test("Matching ignores case and accents")
    func caseAndDiacritics() throws {
        let directory = makeTemporaryDirectory("search-case")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)
        let corpus = makeCorpus(store)

        let exact = ClipboardSearchService.search("hello", in: corpus)
        #expect(try #require(exact.first).item.title == "Hello World")
        #expect(!(try #require(exact.first).ranges.isEmpty))

        #expect(ClipboardSearchService.search("cafe", in: corpus).contains { $0.item.title == "café menu" })
    }

    @Test("Skipping letters still finds the entry")
    func subsequenceMatching() {
        let directory = makeTemporaryDirectory("search-fuzzy")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)
        let corpus = makeCorpus(store)

        #expect(ClipboardSearchService.search("bnotch", in: corpus)
            .contains { $0.item.title.hasPrefix("boring.notch") })
        #expect(ClipboardSearchService.search("zzzqqq", in: corpus).isEmpty)
    }

    @Test("Highlighting never drops any of the text")
    func highlighting() throws {
        let directory = makeTemporaryDirectory("search-highlight")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)
        let corpus = makeCorpus(store)

        let match = try #require(ClipboardSearchService.search("hello", in: corpus).first)
        let highlighted = ClipboardSearchService.highlighted("Hello World", ranges: match.ranges)
        #expect(String(highlighted.characters) == "Hello World")
    }
}

@Suite("Clipboard pasteboard writer")
struct ClipboardPasteboardWriterTests {
    @Test("Copying an entry puts it back on the pasteboard, marked as ours")
    func writesText() {
        let directory = makeTemporaryDirectory("writer")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let item = ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                     data: Data("round-trip payload".utf8))],
            title: "round-trip payload", kind: .text
        )
        let pasteboard = NSPasteboard.withUniqueName()

        #expect(ClipboardPasteboardWriter.write(item, to: pasteboard, blobStore: store))
        #expect(pasteboard.string(forType: .string) == "round-trip payload")
        // Without this marker we would immediately re-record our own paste.
        #expect(pasteboard.data(forType: .fromNotchFun) != nil)
    }

    @Test("Blob-backed payloads are written too")
    func writesBlobBacked() {
        let directory = makeTemporaryDirectory("writer-blob")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let item = ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                     data: Data(repeating: 0x41, count: 50_000))],
            title: "big", kind: .text
        )
        let pasteboard = NSPasteboard.withUniqueName()

        #expect(ClipboardPasteboardWriter.write(item, to: pasteboard, blobStore: store))
        #expect(pasteboard.data(forType: .string)?.count == 50_000)
    }

    @Test("Source attribution rides along")
    func writesSourceApp() {
        let directory = makeTemporaryDirectory("writer-source")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let item = ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                     data: Data("x".utf8))],
            title: "x", kind: .text, appBundleID: "com.example.app"
        )
        let pasteboard = NSPasteboard.withUniqueName()

        ClipboardPasteboardWriter.write(item, to: pasteboard, blobStore: store)
        #expect(pasteboard.string(forType: .source) == "com.example.app")
    }

    @Test("A payload that cannot be read leaves the pasteboard untouched")
    func failureLeavesPasteboardIntact() {
        // The writer gathers everything before clearing, precisely so a missing blob
        // cannot destroy what the user currently has copied.
        let directory = makeTemporaryDirectory("writer-broken")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let existing = NSPasteboardItem()
        existing.setString("existing contents", forType: .string)
        pasteboard.writeObjects([existing])

        let brokenRef = ClipboardContentRef(
            type: NSPasteboard.PasteboardType.string.rawValue,
            data: Data(repeating: 0, count: 10_000),
            blobFilename: "does-not-exist.bin"
        )
        let broken = ClipboardItem(contents: [brokenRef], title: "broken", kind: .text)

        #expect(!ClipboardPasteboardWriter.write(broken, to: pasteboard, blobStore: store))
        #expect(pasteboard.string(forType: .string) == "existing contents")
    }
}
