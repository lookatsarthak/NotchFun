//
//  ClipboardRetentionTests.swift
//  boringNotchTests
//

import AppKit
import Foundation
import Testing

@Suite("Clipboard retention")
struct ClipboardRetentionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    private func item(_ title: String, lastUsed ageInDays: Double, pin: String? = nil, store: ClipboardBlobStore) -> ClipboardItem {
        let used = now.addingTimeInterval(-ageInDays * day)
        return ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(title.utf8))],
            title: title, kind: .text, firstCopiedAt: used, lastCopiedAt: used, pin: pin
        )
    }

    private func withStore(_ body: (ClipboardBlobStore) -> Void) {
        let directory = makeTemporaryDirectory("retention")
        defer { removeDirectory(directory) }
        body(ClipboardBlobStore(directory: directory))
    }

    @Test("Never keeps everything, however old")
    func neverKeepsAll() {
        withStore { store in
            var history = ClipboardHistory(items: [item("ancient", lastUsed: 2000, store: store)])
            #expect(history.removeStale(retention: .never, now: now).isEmpty)
            #expect(history.items.count == 1)
        }
    }

    @Test("A week forgets unpinned clips unused for longer, and keeps recent and pinned ones")
    func weekForgetsStale() {
        withStore { store in
            var history = ClipboardHistory(items: [
                item("recent", lastUsed: 2, store: store),
                item("stale", lastUsed: 10, store: store),
                item("stale but pinned", lastUsed: 400, pin: "b", store: store),
            ])
            let removed = history.removeStale(retention: .week, now: now)
            #expect(removed.map(\.title) == ["stale"])
            #expect(history.items.map(\.title) == ["recent", "stale but pinned"])
        }
    }

    @Test("A clip exactly at the limit stays; a second older goes")
    func boundary() {
        withStore { store in
            var history = ClipboardHistory(items: [
                item("exactly a week", lastUsed: 7, store: store),
                item("a week and a second", lastUsed: 7 + 1 / day, store: store),
            ])
            let removed = history.removeStale(retention: .week, now: now)
            #expect(removed.map(\.title) == ["a week and a second"])
        }
    }

    @Test("Copying a clip again restarts its clock")
    func reuseRestartsClock() {
        withStore { store in
            var history = ClipboardHistory(items: [item("tracking number", lastUsed: 20, store: store)])
            // Copied again today: the new capture carries today's date.
            var again = item("tracking number", lastUsed: 0, store: store)
            again.firstCopiedAt = now
            history.add(again, maxSize: 100)
            #expect(history.removeStale(retention: .week, now: now).isEmpty)
            #expect(history.items.first?.numberOfCopies == 2)
        }
    }

    @Test("Existing users keep everything; new users start at a week")
    func initialChoice() {
        #expect(ClipboardRetention.initial(isExistingUser: true) == .never)
        #expect(ClipboardRetention.initial(isExistingUser: false) == .week)
    }

    @Test("Longer options really are longer")
    func ordering() {
        let intervals = ClipboardRetention.allCases.compactMap(\.interval)
        #expect(intervals == intervals.sorted())
        #expect(ClipboardRetention.never.interval == nil)
    }
}
