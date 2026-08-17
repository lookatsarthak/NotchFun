//
//  ClipboardStorageTests.swift
//  boringNotchTests
//

import AppKit
import Foundation
import Testing

@Suite("Clipboard blob store")
struct ClipboardBlobStoreTests {
    @Test("Small payloads stay inline, large ones spill to a file")
    func inlineVersusBlob() {
        let directory = makeTemporaryDirectory("blobstore")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let small = Data("hello notch".utf8)
        let large = Data(repeating: 0xAB, count: 40_000)
        let smallRef = store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue, data: small)
        let largeRef = store.makeRef(type: NSPasteboard.PasteboardType.png.rawValue, data: large)

        #expect(smallRef.isInline)
        #expect(smallRef.blobFilename == nil)
        #expect(!largeRef.isInline)
        #expect(largeRef.blobFilename != nil)
        #expect(store.data(for: smallRef) == small)
        #expect(store.data(for: largeRef) == large)
        #expect(largeRef.byteCount == 40_000)
    }

    @Test("Digests are stable per payload and differ between payloads")
    func digests() {
        let directory = makeTemporaryDirectory("digest")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let small = Data("hello notch".utf8)
        let smallRef = store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue, data: small)
        let otherRef = store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                     data: Data(repeating: 0xAB, count: 40_000))

        #expect(ClipboardContentRef.digest(of: small) == smallRef.digest)
        #expect(smallRef.digest != otherRef.digest)
    }

    @Test("Clipboard data on disk is not readable by other users")
    func filePermissions() throws {
        let directory = makeTemporaryDirectory("perms")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let ref = store.makeRef(type: NSPasteboard.PasteboardType.png.rawValue,
                                data: Data(repeating: 0xAB, count: 40_000))
        let blobPath = directory
            .appendingPathComponent("blobs")
            .appendingPathComponent(try #require(ref.blobFilename))
            .path

        #expect(try posixPermissions(of: blobPath) == 0o600)
        #expect(try posixPermissions(of: directory.path) == 0o700)
    }
}

@Suite("Clipboard item titles and kinds")
struct ClipboardItemMetadataTests {
    @Test("Titles collapse whitespace into something readable in one line")
    func titleWhitespace() {
        let directory = makeTemporaryDirectory("title")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let ref = store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                data: Data("  line one\nline two\t\tend  ".utf8))
        let title = ClipboardItem.makeTitle(contents: [ref], kind: .text) { store.data(for: $0) }
        #expect(title == "line one line two end")
    }

    @Test("Kinds are inferred from content")
    func kinds() {
        let directory = makeTemporaryDirectory("kind")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let textRef = store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                    data: Data("just some words".utf8))
        let urlRef = store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                   data: Data("https://github.com/TheBoredTeam/boring.notch".utf8))
        let imageRef = store.makeRef(type: NSPasteboard.PasteboardType.png.rawValue,
                                     data: Data(repeating: 0xAB, count: 40_000))

        let urlTitle = ClipboardItem.makeTitle(contents: [urlRef], kind: .text) { store.data(for: $0) }
        let textTitle = ClipboardItem.makeTitle(contents: [textRef], kind: .text) { store.data(for: $0) }

        #expect(ClipboardItem.makeKind(contents: [urlRef], title: urlTitle) == .link)
        #expect(ClipboardItem.makeKind(contents: [textRef], title: textTitle) == .text)
        #expect(ClipboardItem.makeKind(contents: [imageRef], title: "") == .image)
    }

    @Test("Styled text yields a plain readable title")
    func richTextTitle() throws {
        let directory = makeTemporaryDirectory("rtf")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let source = NSAttributedString(string: "styled clip")
        let rtf = try #require(source.rtf(from: NSRange(location: 0, length: source.length),
                                         documentAttributes: [:]))
        let ref = store.makeRef(type: NSPasteboard.PasteboardType.rtf.rawValue, data: rtf)

        let title = ClipboardItem.makeTitle(contents: [ref], kind: .text) { store.data(for: $0) }
        #expect(title == "styled clip")
    }
}

@Suite("Clipboard dedupe")
struct ClipboardDedupeTests {
    @Test("Identical payloads are duplicates, different ones are not")
    func supersedes() {
        let directory = makeTemporaryDirectory("dedupe")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)
        let payload = Data("hello notch".utf8)

        func ref(_ data: Data, type: NSPasteboard.PasteboardType = .string) -> ClipboardContentRef {
            store.makeRef(type: type.rawValue, data: data)
        }

        let first = ClipboardItem(contents: [ref(payload)], title: "hello notch", kind: .text)
        let sameBytes = ClipboardItem(contents: [ref(payload)], title: "hello notch", kind: .text)
        let different = ClipboardItem(contents: [ref(Data("other".utf8))], title: "other", kind: .text)

        #expect(first.supersedes(sameBytes))
        #expect(!first.supersedes(different))
    }

    @Test("A clip differing only by source attribution is still a duplicate")
    func transientTypesIgnored() {
        // Otherwise copying the same text from two apps would produce two rows.
        let directory = makeTemporaryDirectory("dedupe-transient")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)
        let payload = Data("hello notch".utf8)

        let plain = ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue, data: payload)],
            title: "hello notch", kind: .text
        )
        let withSource = ClipboardItem(contents: [
            store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue, data: payload),
            store.makeRef(type: NSPasteboard.PasteboardType.source.rawValue,
                          data: Data("com.apple.Safari".utf8)),
        ], title: "hello notch", kind: .text)

        #expect(plain.supersedes(withSource))
    }
}

@Suite("Clipboard persistence")
@MainActor
struct ClipboardPersistenceTests {
    @Test("History survives a round-trip to disk")
    func roundTrip() async throws {
        let directory = makeTemporaryDirectory("persist")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)
        let large = Data(repeating: 0xAB, count: 40_000)

        let text = ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                     data: Data("hello notch".utf8))],
            title: "hello notch", kind: .text
        )
        let other = ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                     data: Data("other".utf8))],
            title: "other", kind: .text
        )
        let image = ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.png.rawValue, data: large)],
            title: "", kind: .image, pin: "p"
        )
        let items = [text, other, image]

        let service = ClipboardPersistenceService(blobStore: store)
        await service.flush(items)
        let loaded = service.load()

        #expect(loaded.count == 3)
        #expect(loaded.map(\.id) == items.map(\.id))
        #expect(loaded[2].pin == "p")
        #expect(loaded[2].kind == .image)
        #expect(store.data(for: loaded[2].contents[0]) == large)
        #expect(try posixPermissions(of: directory.appendingPathComponent("index.json").path) == 0o600)
    }

    @Test("Blobs belonging to forgotten items are cleaned up")
    func orphanPruning() async {
        let directory = makeTemporaryDirectory("prune")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let keep = ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                     data: Data("keep".utf8))],
            title: "keep", kind: .text
        )
        let drop = ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.png.rawValue,
                                     data: Data(repeating: 0xAB, count: 40_000))],
            title: "", kind: .image
        )

        let service = ClipboardPersistenceService(blobStore: store)
        await service.flush([keep, drop])

        store.pruneOrphans(keeping: [keep])
        #expect(store.data(for: drop.contents[0]) == nil)
    }

    @Test("One corrupt record does not lose the rest of the history")
    func salvagesPastCorruptRecords() async throws {
        let directory = makeTemporaryDirectory("salvage")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let good = ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                     data: Data("hello notch".utf8))],
            title: "hello notch", kind: .text
        )
        let service = ClipboardPersistenceService(blobStore: store)
        await service.flush([good])

        let encoded = String(decoding: try JSONEncoder.notchFunISO8601.encode(good), as: UTF8.self)
        let corrupt = #"{"schemaVersion":1,"items":[{"totally":"broken"},\#(encoded)]}"#
        try Data(corrupt.utf8).write(to: directory.appendingPathComponent("index.json"))

        let salvaged = service.load()
        #expect(salvaged.count == 1)
        #expect(salvaged.first?.id == good.id)
    }
}
