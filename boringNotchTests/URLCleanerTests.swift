//
//  URLCleanerTests.swift
//  boringNotchTests
//

import AppKit
import Foundation
import Testing

/// The asymmetry these tests encode: removing a tracker the user wanted is a nuisance,
/// but keeping a link that no longer works is a broken feature. Most of what follows
/// checks that the cleaner leaves things alone.
@Suite("URL cleaning")
struct URLCleanerTests {

    // MARK: - Things that must never be touched

    @Test("Anything that is not a single http(s) URL is left alone", arguments: [
        "",
        "   ",
        "just some text",
        "Look at https://example.com/?utm_source=x for details",   // a URL inside a sentence
        "https://example.com/path",                                // no query at all
        "example.com/?utm_source=x",                               // no scheme
        "mailto:someone@example.com?utm_source=x",                 // not http
        "file:///Users/me/notes.txt?utm_source=x",
        "javascript:alert(1)?utm_source=x",
        "ftp://example.com/?utm_source=x",
    ])
    func nonURLsIgnored(text: String) {
        #expect(URLCleaner.clean(text) == nil)
    }

    @Test("A URL with no tracking parameters comes back untouched", arguments: [
        "https://example.com/search?q=notch&page=2",
        "https://developer.apple.com/documentation/swiftui?language=swift",
        "https://example.com/?a=1&b=2&c=3",
    ])
    func cleanURLsUnchanged(text: String) {
        // nil, not "the same string": returning the input would send it through
        // URLComponents' re-encoder, which can change a URL that had nothing wrong
        // with it. Only a real removal is allowed to rewrite anything.
        #expect(URLCleaner.clean(text) == nil)
    }

    @Test("Parameters that carry content are never removed")
    func contentParametersSurvive() {
        // The single worst failure this feature could have: a YouTube link that loses
        // its video id, its timestamp or its playlist position.
        let result = URLCleaner.clean(
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s&list=PL123&index=3&si=AbCdEf"
        )
        let cleaned = try! #require(result).cleaned
        #expect(cleaned.contains("v=dQw4w9WgXcQ"))
        #expect(cleaned.contains("t=42s"))
        #expect(cleaned.contains("list=PL123"))
        #expect(cleaned.contains("index=3"))
        #expect(!cleaned.contains("si="))
    }

    @Test("An ambiguous name is only a tracker on the hosts where it is one")
    func scopedNamesRespectHost() {
        // `si` is a share token on YouTube and an ordinary parameter on a blog.
        #expect(URLCleaner.clean("https://myblog.example/post?si=sidebar") == nil)
        #expect(URLCleaner.clean("https://youtu.be/abc123?si=XYZ") != nil)

        // `s` and `t` on x.com, but not anywhere else.
        #expect(URLCleaner.clean("https://shop.example/item?s=medium&t=blue") == nil)
        #expect(URLCleaner.clean("https://x.com/user/status/1?s=20&t=abc") != nil)
    }

    // MARK: - Things that must be removed

    @Test("Every utm_ parameter goes, whatever the suffix")
    func utmPrefix() {
        let result = try! #require(URLCleaner.clean(
            "https://example.com/article?utm_source=newsletter&utm_medium=email&utm_campaign=spring&utm_content=cta&id=99"
        ))
        #expect(result.cleaned == "https://example.com/article?id=99")
        #expect(result.removed.count == 4)
    }

    @Test("Common click identifiers are removed everywhere", arguments: [
        "fbclid", "gclid", "msclkid", "twclid", "ttclid", "igshid", "mc_eid", "yclid",
        "dclid", "gbraid", "wbraid", "mkt_tok", "_hsenc", "irclickid",
    ])
    func globalTrackers(name: String) {
        let result = try! #require(URLCleaner.clean("https://example.com/p?\(name)=abc123&keep=1"))
        #expect(result.cleaned == "https://example.com/p?keep=1")
        #expect(result.removed == [name])
    }

    @Test("Parameter names match case-insensitively")
    func caseInsensitive() {
        let result = try! #require(URLCleaner.clean("https://example.com/?UTM_Source=x&FBCLID=y&keep=1"))
        #expect(result.cleaned == "https://example.com/?keep=1")
        #expect(result.removed.count == 2)
        // The names are reported as they were written, not lowercased.
        #expect(result.removed.contains("UTM_Source"))
    }

    @Test("A URL that was only tracking loses its query entirely, not just its contents")
    func queryFullyRemoved() {
        // A trailing "?" is the tell-tale of a naive implementation, and some servers
        // treat it differently from no query at all.
        let result = try! #require(URLCleaner.clean("https://example.com/page?utm_source=x&fbclid=y"))
        #expect(result.cleaned == "https://example.com/page")
        #expect(!result.cleaned.hasSuffix("?"))
    }

    @Test("Amazon's storefronts all share one parameter set")
    func amazonStorefronts() {
        for host in ["www.amazon.com", "www.amazon.co.uk", "www.amazon.in", "www.amazon.co.jp"] {
            let result = URLCleaner.clean("https://\(host)/dp/B01ABCDEFG?ref=sr_1_1&psc=1&tag=aff-20")
            #expect(result?.cleaned == "https://\(host)/dp/B01ABCDEFG", "failed for \(host)")
        }
    }

    @Test("Subdomains inherit their host's rules")
    func subdomainsMatch() {
        #expect(URLCleaner.clean("https://music.youtube.com/watch?v=x&si=abc") != nil)
        #expect(URLCleaner.clean("https://open.spotify.com/track/x?si=abc") != nil)
        // ...but a host that merely ends in the same letters does not.
        #expect(URLCleaner.clean("https://notyoutube.com/watch?si=abc") == nil)
        #expect(URLCleaner.clean("https://myx.com/status?s=20") == nil)
    }

    // MARK: - Shape of the result

    @Test("The rest of the URL survives cleaning intact")
    func remainderPreserved() {
        let result = try! #require(URLCleaner.clean(
            "https://user@example.com:8443/a/b/c?utm_source=x&q=hello#section-2"
        ))
        #expect(result.cleaned == "https://user@example.com:8443/a/b/c?q=hello#section-2")
    }

    @Test("Surrounding whitespace and newlines are trimmed away")
    func trimsWhitespace() {
        let result = try! #require(URLCleaner.clean("\n  https://example.com/?utm_source=x&k=1  \n"))
        #expect(result.cleaned == "https://example.com/?k=1")
    }

    @Test("A parameter with no value is still recognised")
    func valuelessParameter() {
        let result = try! #require(URLCleaner.clean("https://example.com/?fbclid&keep=1"))
        #expect(result.cleaned == "https://example.com/?keep=1")
    }

    @Test("wouldClean agrees with clean")
    func predicateMatchesResult() {
        #expect(URLCleaner.wouldClean("https://example.com/?utm_source=x"))
        #expect(!URLCleaner.wouldClean("https://example.com/?q=x"))
        #expect(!URLCleaner.wouldClean("not a url"))
    }
}

/// Covers the wiring rather than the algorithm: that the flag reaches the pasteboard,
/// that a clean link is left completely alone, and that nothing else is affected.
/// Every test uses `NSPasteboard.withUniqueName()`, so the real clipboard is untouched.
@Suite("Link cleaning on write", .serialized)
struct ClipboardLinkCleaningTests {

    private func makeTextItem(_ text: String, store: ClipboardBlobStore) -> ClipboardItem {
        ClipboardItem(
            contents: [store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue,
                                     data: Data(text.utf8))],
            title: text, kind: .text
        )
    }

    private func makeRichItem(_ text: String, html: String, store: ClipboardBlobStore) -> ClipboardItem {
        ClipboardItem(
            contents: [
                store.makeRef(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8)),
                store.makeRef(type: NSPasteboard.PasteboardType.html.rawValue, data: Data(html.utf8)),
            ],
            title: text, kind: .text
        )
    }

    @Test("With the setting off, a tracked link is pasted exactly as copied")
    func offIsAPassthrough() {
        let directory = makeTemporaryDirectory("clean-off")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)
        let dirty = "https://example.com/a?utm_source=x&id=1"

        let pasteboard = NSPasteboard.withUniqueName()
        #expect(ClipboardPasteboardWriter.write(makeTextItem(dirty, store: store),
                                                to: pasteboard, blobStore: store, cleanLinks: false))
        #expect(pasteboard.string(forType: .string) == dirty)
    }

    @Test("With the setting on, the tracker is gone from what is pasted")
    func onRewritesTheLink() {
        let directory = makeTemporaryDirectory("clean-on")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let pasteboard = NSPasteboard.withUniqueName()
        #expect(ClipboardPasteboardWriter.write(
            makeTextItem("https://example.com/a?utm_source=x&id=1", store: store),
            to: pasteboard, blobStore: store, cleanLinks: true))
        #expect(pasteboard.string(forType: .string) == "https://example.com/a?id=1")
    }

    @Test("A tracked link is written as plain text only, never half-cleaned")
    func richLinkLosesItsOtherRepresentations() {
        // The failure this prevents: cleaning the plain text but leaving the HTML anchor
        // pointing at the tracked URL, so the setting works in some apps and not others.
        let directory = makeTemporaryDirectory("clean-rich")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)
        let item = makeRichItem("https://example.com/a?fbclid=xyz",
                                html: "<a href=\"https://example.com/a?fbclid=xyz\">link</a>",
                                store: store)

        let pasteboard = NSPasteboard.withUniqueName()
        #expect(ClipboardPasteboardWriter.write(item, to: pasteboard, blobStore: store, cleanLinks: true))
        #expect(pasteboard.string(forType: .string) == "https://example.com/a")
        #expect(pasteboard.data(forType: .html) == nil)
    }

    @Test("A link with nothing to clean keeps every representation it had")
    func untrackedLinkKeepsRichContent() {
        let directory = makeTemporaryDirectory("clean-noop")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)
        let item = makeRichItem("https://example.com/a?id=1",
                                html: "<a href=\"https://example.com/a?id=1\">link</a>",
                                store: store)

        let pasteboard = NSPasteboard.withUniqueName()
        #expect(ClipboardPasteboardWriter.write(item, to: pasteboard, blobStore: store, cleanLinks: true))
        #expect(pasteboard.string(forType: .string) == "https://example.com/a?id=1")
        #expect(pasteboard.data(forType: .html) != nil)
    }

    @Test("Ordinary text is untouched even with the setting on")
    func plainTextUnaffected() {
        let directory = makeTemporaryDirectory("clean-text")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)
        let note = "remember to check utm_source in the analytics dashboard"

        let pasteboard = NSPasteboard.withUniqueName()
        #expect(ClipboardPasteboardWriter.write(makeTextItem(note, store: store),
                                                to: pasteboard, blobStore: store, cleanLinks: true))
        #expect(pasteboard.string(forType: .string) == note)
    }

    @Test("Paste-as-plain-text cleans the link too")
    func plainTextPathAlsoCleans() {
        // Otherwise the two paste routes would disagree, which is the kind of
        // inconsistency that reads as a bug rather than a setting.
        let directory = makeTemporaryDirectory("clean-plain")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let pasteboard = NSPasteboard.withUniqueName()
        #expect(ClipboardPasteboardWriter.writePlainText(
            makeTextItem("https://example.com/a?gclid=z&keep=2", store: store),
            to: pasteboard, blobStore: store, cleanLinks: true))
        #expect(pasteboard.string(forType: .string) == "https://example.com/a?keep=2")
    }

    @Test("The write is still stamped as ours, so the monitor does not re-record it")
    func selfCopyMarkerSurvivesCleaning() {
        // Without this the cleaned URL would be captured as a brand new copy on the next
        // poll, and history would fill with cleaned duplicates of itself.
        let directory = makeTemporaryDirectory("clean-marker")
        defer { removeDirectory(directory) }
        let store = ClipboardBlobStore(directory: directory)

        let pasteboard = NSPasteboard.withUniqueName()
        #expect(ClipboardPasteboardWriter.write(
            makeTextItem("https://example.com/a?utm_source=x", store: store),
            to: pasteboard, blobStore: store, cleanLinks: true))
        #expect(pasteboard.data(forType: .fromNotchFun) != nil)
    }
}
