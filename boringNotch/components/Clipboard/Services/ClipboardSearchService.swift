//
//  ClipboardSearchService.swift
//  boringNotch
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
        /// Ranges of `item.title` that matched, for highlighting.
        let ranges: [Range<String.Index>]
    }

    static func search(_ query: String, in items: [ClipboardItem]) -> [Match] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return items.map { Match(item: $0, ranges: []) }
        }

        var exact: [Match] = []
        var fuzzy: [Match] = []

        for item in items {
            if let range = item.title.range(
                of: trimmed,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) {
                exact.append(Match(item: item, ranges: [range]))
            } else if let ranges = subsequenceRanges(of: trimmed, in: item.title) {
                fuzzy.append(Match(item: item, ranges: ranges))
            }
        }

        // Exact hits first; both groups keep the history's own recency order.
        return exact + fuzzy
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
