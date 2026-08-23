//
//  ClipboardCaptureTests.swift
//  boringNotchTests
//

import AppKit
import Foundation
import Testing

/// Every test here uses `NSPasteboard.withUniqueName()`, so the real system clipboard is
/// never read or written — running the suite must not disturb whatever the user copied.
/// Serialized: every test here creates a uniquely named NSPasteboard, and running them
/// concurrently occasionally produced a pasteboard that returned nothing at all - a flake
/// in the harness rather than the product, but a flake either way.
@Suite("Clipboard capture filtering", .serialized)
struct ClipboardCaptureTests {
    private func capture(_ pasteboard: NSPasteboard, store: ClipboardBlobStore) -> ClipboardItem? {
        guard let snapshot = ClipboardCapture.snapshot(
            from: pasteboard,
            sourceAppBundleID: "com.example.test",
            config: .default
        ) else { return nil }
        return ClipboardCapture.makeItem(from: snapshot, blobStore: store)
    }

    @Test("Passwords are never recorded", arguments: [
        "concealed", "transient", "legacy-password-manager",
    ])
    func secretsAreSkipped(variant: String) {
        // The nspasteboard.org convention: password managers mark their copies, and we
        // must honour that. A clipboard manager that records passwords is a liability.
        let directory = makeTemporaryDirectory("secrets")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)
        let pasteboard = NSPasteboard.withUniqueName()

        switch variant {
        case "concealed":
            pasteboard.declareTypes([.string, .concealed], owner: nil)
            pasteboard.setString("hunter2", forType: .string)
            pasteboard.setString("", forType: .concealed)
        case "transient":
            pasteboard.declareTypes([.string, .transient], owner: nil)
            pasteboard.setString("temp", forType: .string)
        default:
            let onePassword = NSPasteboard.PasteboardType("com.agilebits.onepassword")
            pasteboard.declareTypes([.string, onePassword], owner: nil)
            pasteboard.setString("secret", forType: .string)
            pasteboard.setString("x", forType: onePassword)
        }

        #expect(capture(pasteboard, store: store) == nil)
    }

    @Test("Our own paste is not recorded again")
    func selfCopyIgnored() {
        let directory = makeTemporaryDirectory("selfcopy")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.declareTypes([.string, .fromNotchFun], owner: nil)
        pasteboard.setString("pasted by us", forType: .string)
        pasteboard.setString("", forType: .fromNotchFun)

        #expect(capture(pasteboard, store: store) == nil)
    }

    @Test("Whitespace-only copies are ignored")
    func blankIgnored() {
        let directory = makeTemporaryDirectory("blank")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("   \n\t ", forType: .string)

        #expect(capture(pasteboard, store: store) == nil)
    }

    @Test("Ordinary text is captured with its source app")
    func textCaptured() {
        let directory = makeTemporaryDirectory("text")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("Hello from the notch", forType: .string)

        let item = capture(pasteboard, store: store)
        #expect(item != nil)
        #expect(item?.title == "Hello from the notch")
        #expect(item?.kind == .text)
        #expect(item?.appBundleID == "com.example.test")
    }

    @Test("Junk pasteboard types are stripped but real ones kept")
    func noiseTypesStripped() {
        let directory = makeTemporaryDirectory("noise")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let dynamic = NSPasteboard.PasteboardType("dyn.ah62d4rv4gu8zg55usm1044pxqzb085xyqz1hk64uqm10c6xenv61a3k")
        let microsoft = NSPasteboard.PasteboardType("com.microsoft.ole.source.xyz")
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.declareTypes([.string, dynamic, microsoft], owner: nil)
        pasteboard.setString("clip", forType: .string)
        pasteboard.setString("junk", forType: dynamic)
        pasteboard.setString("junk", forType: microsoft)

        let types = Set(capture(pasteboard, store: store)?.contents.map(\.type) ?? [])
        #expect(!types.contains(dynamic.rawValue))
        #expect(!types.contains(microsoft.rawValue))
        #expect(types.contains(NSPasteboard.PasteboardType.string.rawValue))
    }

    @Test("A multi-item copy becomes a single history entry")
    func multiItemCopy() {
        let directory = makeTemporaryDirectory("multi")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let first = NSPasteboardItem(); first.setString("first", forType: .string)
        let second = NSPasteboardItem(); second.setString("second", forType: .string)
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])

        #expect(capture(pasteboard, store: store) != nil)
    }

    @Test("Stored type order is deterministic")
    func typeOrderStable() {
        // Order feeds the dedupe digest, so it has to be stable across captures.
        let resolved = ClipboardCapture.resolvedTypes(for: [.string, .rtf, .html])
        #expect(resolved == resolved.sorted { $0.rawValue < $1.rawValue })
    }
}

@Suite("Clipboard history rules")
struct ClipboardHistoryTests {
    private func makeItem(_ title: String, store: ClipboardBlobStore, pin: String? = nil) -> ClipboardItem {
        ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                     data: Data(title.utf8))],
            title: title, kind: .text, pin: pin
        )
    }

    @Test("Newest copies come first")
    func ordering() {
        let directory = makeTemporaryDirectory("history-order")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        var history = ClipboardHistory()
        history.add(makeItem("one", store: store), maxSize: 100)
        history.add(makeItem("two", store: store), maxSize: 100)

        #expect(history.items.first?.title == "two")
        #expect(history.items.count == 2)
    }

    @Test("Re-copying something moves it to the top and counts it")
    func duplicates() {
        let directory = makeTemporaryDirectory("history-dupe")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        var history = ClipboardHistory()
        history.add(makeItem("one", store: store), maxSize: 100)
        history.add(makeItem("two", store: store), maxSize: 100)

        let result = history.add(makeItem("one", store: store), maxSize: 100)
        #expect(result.wasDuplicate)
        #expect(history.items.count == 2)
        #expect(history.items.first?.title == "one")
        #expect(history.items.first?.numberOfCopies == 2)
    }

    @Test("Trimming removes the oldest unpinned entries and spares pinned ones")
    func limitSparesPinned() throws {
        let directory = makeTemporaryDirectory("history-limit")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        var history = ClipboardHistory()
        for i in 1...5 { history.add(makeItem("item\(i)", store: store), maxSize: 100) }
        history.togglePin(id: try #require(history.items.last).id)   // pin the oldest
        let pinnedTitle = history.items.first(where: \.isPinned)?.title

        let evicted = history.enforceLimit(2)
        #expect(history.unpinned.count == 2)
        #expect(history.items.contains { $0.title == pinnedTitle })
        #expect(evicted.count == 2)
        // Pinned items are exempt, so the total can exceed the limit.
        #expect(history.items.count == 3)
    }

    @Test("Each pin gets its own shortcut character")
    func pinsAreDistinct() {
        let directory = makeTemporaryDirectory("history-pins")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        var history = ClipboardHistory()
        for i in 1...3 { history.add(makeItem("p\(i)", store: store), maxSize: 100) }
        history.items.forEach { history.togglePin(id: $0.id) }

        #expect(Set(history.items.compactMap(\.pin)).count == 3)
    }
}

/// Serialized: these drive a real polling timer, and running them concurrently with the
/// rest of the suite makes the timing assertions flaky.
@Suite("Clipboard monitor", .serialized)
@MainActor
struct ClipboardMonitorTests {
    @Test("Polling notices a copy exactly once")
    func capturesOnce() async {
        let directory = makeTemporaryDirectory("monitor")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, blobStore: store)
        var captured: [ClipboardItem] = []
        monitor.setHandler { captured.append($0) }

        var config = ClipboardCaptureConfig.default
        config.pollInterval = 0.1
        monitor.start(config: config)

        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("monitored clip", forType: .string)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(captured.count == 1)
        #expect(captured.first?.title == "monitored clip")

        // Nothing changed, so nothing more should be recorded.
        try? await Task.sleep(for: .milliseconds(400))
        #expect(captured.count == 1)

        monitor.stop()
    }

    @Test("Suspending stops capture, and resuming does not backfill")
    func suspendResume() async {
        let directory = makeTemporaryDirectory("monitor-suspend")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, blobStore: store)
        var captured: [ClipboardItem] = []
        monitor.setHandler { captured.append($0) }

        var config = ClipboardCaptureConfig.default
        config.pollInterval = 0.1
        monitor.start(config: config)

        monitor.suspend()
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("while suspended", forType: .string)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(captured.isEmpty)

        // Resuming must not sweep up what was copied while we were not watching:
        // that content was deliberately skipped, most likely because we pasted it.
        monitor.resume()
        try? await Task.sleep(for: .milliseconds(400))
        #expect(captured.isEmpty)

        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("after resume", forType: .string)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(captured.count == 1)

        monitor.stop()
    }

    @Test("A stopped monitor records nothing")
    func stopped() async {
        let directory = makeTemporaryDirectory("monitor-stop")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, blobStore: store)
        var captured: [ClipboardItem] = []
        monitor.setHandler { captured.append($0) }

        var config = ClipboardCaptureConfig.default
        config.pollInterval = 0.1
        monitor.start(config: config)
        monitor.stop()

        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("after stop", forType: .string)
        try? await Task.sleep(for: .milliseconds(400))

        #expect(captured.isEmpty)
    }
}
