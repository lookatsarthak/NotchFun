//
//  ClipboardSearchService.swift
//  NotchFun
//

import Foundation

/// Filters history titles.
///
/// Exact substring first; if that finds nothing, a subsequence match so "bnotch"
/// still finds "boring.notch". Deliberately dependency-free — Maccy pulls in Fuse for
/// this, which is more machinery than a single-line title list needs.
enum ClipboardSearchService {

    struct Match {
        let item: ClipboardItem
        /// Ranges that matched, for highlighting: in `item.title`, or in `displayTitle`
        /// when there is one.
        let ranges: [Range<String.Index>]
        /// For an image found by the text in it: the line that matched, shown in place of
        /// the image's title so you can see why it's in the results.
        var displayTitle: String? = nil
    }

    static func search(_ query: String, in items: [ClipboardItem]) -> [Match] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return items.map { Match(item: $0, ranges: []) }
        }

        var exact: [Match] = []
        var inImages: [Match] = []
        var fuzzy: [Match] = []

        for item in items {
            if let range = item.title.range(
                of: trimmed,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) {
                exact.append(Match(item: item, ranges: [range]))
            } else if let match = contentMatch(trimmed, in: item) {
                inImages.append(match)
            } else if let ranges = subsequenceRanges(of: trimmed, in: item.title) {
                fuzzy.append(Match(item: item, ranges: ranges))
            }
        }

        // Exact title hits first, then images whose text contains the query, then the
        // loose in-order matches; each group keeps the history's own recency order. Text
        // in images is only matched exactly: read text is noisy, and loose matching over
        // a page of it would find almost anything.
        return exact + inImages + fuzzy
    }

    /// A match inside an image's text, shown as the line that matched, or inside a
    /// snippet's text, shown under the snippet's own name.
    private static func contentMatch(_ query: String, in item: ClipboardItem) -> Match? {
        if let snippet = item.snippetText {
            return snippet.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                ? Match(item: item, ranges: []) : nil
        }
        guard let text = item.imageText else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let line = String(line).trimmingCharacters(in: .whitespaces)
            if let range = line.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
                return Match(item: item, ranges: [range], displayTitle: line)
            }
        }
        return nil
    }

    /// Matches every character of `needle` in order within `haystack`, returning the
    /// range of each matched character.
    private static func subsequenceRanges(of needle: String, in haystack: String) -> [Range<String.Index>]? {
        let target = haystack.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let query = needle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !query.isEmpty, target.count == haystack.count else { return nil }

        var ranges: [Range<String.Index>] = []
        var cursor = target.startIndex

        for character in query where character != " " {
            guard let found = target[cursor...].firstIndex(of: character) else { return nil }
            ranges.append(found..<target.index(after: found))
            cursor = target.index(after: found)
        }
        return ranges.isEmpty ? nil : ranges
    }

    /// Builds the row label with matched characters emphasised.
    static func highlighted(_ title: String, ranges: [Range<String.Index>]) -> AttributedString {
        var attributed = AttributedString(title)
        guard !ranges.isEmpty else { return attributed }

        for range in ranges {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }
}
