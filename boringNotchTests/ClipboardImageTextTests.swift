//
//  ClipboardImageTextTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Finding copied images by their text")
struct ClipboardImageTextTests {

    private func image(_ text: String?, title: String = "Image") -> ClipboardItem {
        var item = ClipboardItem(contents: [], title: title, kind: .image)
        item.imageText = text
        return item
    }

    private func text(_ title: String) -> ClipboardItem {
        ClipboardItem(contents: [], title: title, kind: .text)
    }

    @Test("An image is found by a word in it, showing the line that matched")
    func findsImage() throws {
        let shot = image("Invoice #4821\nTotal due: $320.00\nPay by 30 Nov")
        let matches = ClipboardSearchService.search("total due", in: [text("hello"), shot])
        let match = try #require(matches.first)
        #expect(matches.count == 1)
        #expect(match.item.id == shot.id)
        #expect(match.displayTitle == "Total due: $320.00")
        #expect(match.ranges.count == 1)
        #expect(String(match.displayTitle![match.ranges[0]]) == "Total due")
    }

    @Test("Title matches come before image-text matches, which come before loose matches")
    func ordering() {
        let titled = text("invoice from Acme")
        let shot = image("Invoice #4821")
        let loose = text("in vo ic e")
        let ids = ClipboardSearchService.search("invoice", in: [loose, shot, titled]).map(\.item.id)
        #expect(ids == [titled.id, shot.id, loose.id])
    }

    @Test("Image text is matched exactly, never loosely")
    func noFuzzyInImages() {
        let shot = image("a page of words in no particular order at all")
        #expect(ClipboardSearchService.search("apwnpo", in: [shot]).isEmpty)
    }

    @Test("Images without text, and an empty query, behave as before")
    func unchanged() {
        let plain = image(nil)
        #expect(ClipboardSearchService.search("anything", in: [plain]).isEmpty)
        let all = ClipboardSearchService.search("  ", in: [plain])
        #expect(all.count == 1)
        #expect(all.first?.displayTitle == nil)
    }

    @Test("History saved before image text existed still loads")
    func legacyHistory() throws {
        let legacy = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","contents":[],"title":"Image","kind":"image",
         "firstCopiedAt":0,"lastCopiedAt":0,"numberOfCopies":1}
        """
        let item = try JSONDecoder().decode(ClipboardItem.self, from: Data(legacy.utf8))
        #expect(item.imageText == nil)
        let encoded = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        #expect(!encoded.contains("imageText"))
    }

    @Test("Text that looks like a secret is the kind that gets dropped")
    func secretsDropped() {
        #expect(ClipboardSecretHeuristic.looksSensitive("api_key: sk-live-9f8e7d6c5b4a3f2e1d0c"))
        #expect(!ClipboardSecretHeuristic.looksSensitive("Total due: $320.00"))
    }
}
