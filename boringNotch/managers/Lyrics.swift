//
//  Lyrics.swift
//  NotchFun
//

import Foundation

/// One timed line of synced lyrics.
struct LyricLine: Equatable, Sendable {
    /// Seconds from the start of the track.
    let time: Double
    let text: String
}

/// The pure parts of lyrics: reading LRC, choosing the right search result, and finding the
/// line being sung. Network and AppleScript stay in `MusicManager`; everything here is
/// testable without either.
enum Lyrics {

    // MARK: - LRC

    /// Reads LRC text (`[mm:ss.xx] words`) into lines sorted by time.
    ///
    /// - The fraction can have one, two or three digits, and means tenths, hundredths or
    ///   thousandths respectively. The old parser took only two, dropped every line written
    ///   with milliseconds, and read `.5` as five hundredths.
    /// - One line may carry several stamps (`[00:12.00][01:40.00] chorus`); each becomes a line.
    /// - Tag lines such as `[ar: Artist]` and lines with no words are skipped.
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for rawLine in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(rawLine)
            var stamps: [Double] = []
            while let stamp = leadingStamp(in: rest) {
                stamps.append(stamp.time)
                rest = rest[stamp.end...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            guard !stamps.isEmpty, !text.isEmpty else { continue }
            lines += stamps.map { LyricLine(time: $0, text: text) }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// `[m:ss]`, `[mm:ss.f]`, `[mm:ss.ff]` or `[mm:ss.fff]` at the start of `text`.
    private static func leadingStamp(in text: Substring) -> (time: Double, end: Substring.Index)? {
        let trimmed = text.drop(while: { $0 == " " })
        guard trimmed.first == "[", let close = trimmed.firstIndex(of: "]") else { return nil }
        let inside = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
        let parts = inside.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              (1...3).contains(parts[0].count), parts[0].allSatisfy(\.isASCIIDigit),
              let minutes = Double(parts[0]) else { return nil }
        let secondsParts = parts[1].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard secondsParts[0].count == 2, secondsParts[0].allSatisfy(\.isASCIIDigit),
              let seconds = Double(secondsParts[0]), seconds < 60 else { return nil }
        var fraction = 0.0
        if secondsParts.count == 2 {
            let digits = secondsParts[1]
            guard (1...3).contains(digits.count), digits.allSatisfy(\.isASCIIDigit),
                  let value = Double(digits) else { return nil }
            fraction = value / pow(10, Double(digits.count))
        }
        return (minutes * 60 + seconds + fraction, trimmed.index(after: close))
    }

    // MARK: - Which line is being sung

    /// The index of the line being sung at `elapsed`, or nil before the first line starts.
    static func lineIndex(at elapsed: Double, in lines: [LyricLine]) -> Int? {
        guard let first = lines.first, elapsed >= first.time else { return nil }
        var low = 0, high = lines.count - 1, found = 0
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= elapsed { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }

    /// When each line after `elapsed` starts, as dates, given the playback clock: the
    /// schedule for a view that changes once per line and draws nothing in between.
    static func upcomingLineDates(after elapsed: Double, in lines: [LyricLine],
                                  clockDate: Date, clockElapsed: Double, rate: Double) -> [Date] {
        guard rate > 0 else { return [] }
        return lines.lazy
            .filter { $0.time > elapsed }
            .prefix(64)
            .map { clockDate.addingTimeInterval(($0.time - clockElapsed) / rate) }
    }

    // MARK: - Choosing a search result

    /// One LRCLIB search result, the fields that matter.
    struct Candidate: Equatable, Sendable {
        var trackName: String
        var artistName: String
        var duration: Double?
        var plainLyrics: String
        var syncedLyrics: String

        init(trackName: String, artistName: String, duration: Double?, plainLyrics: String, syncedLyrics: String) {
            self.trackName = trackName
            self.artistName = artistName
            self.duration = duration
            self.plainLyrics = plainLyrics
            self.syncedLyrics = syncedLyrics
        }

        init?(json: [String: Any]) {
            guard let name = json["trackName"] as? String else { return nil }
            trackName = name
            artistName = json["artistName"] as? String ?? ""
            duration = (json["duration"] as? NSNumber)?.doubleValue
            plainLyrics = (json["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            syncedLyrics = (json["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        var hasLyrics: Bool { !plainLyrics.isEmpty || !syncedLyrics.isEmpty }
    }

    /// The result most likely to be this recording, or nil when none is a plausible match.
    ///
    /// LRCLIB's search returns covers, live versions and other songs with the same words in
    /// the title, often first. A result must match the title; artist, a duration within a
    /// few seconds and having synced lyrics then rank it. A result whose length is far off
    /// is a different recording and loses even with the right title.
    static func bestMatch(in candidates: [Candidate], title: String, artist: String, duration: Double?) -> Candidate? {
        let wantTitle = comparable(title)
        let wantArtist = comparable(artist)
        guard !wantTitle.isEmpty else { return nil }

        func score(_ c: Candidate) -> Int? {
            guard c.hasLyrics else { return nil }
            let gotTitle = comparable(c.trackName)
            var score: Int
            if gotTitle == wantTitle { score = 10 }
            else if !gotTitle.isEmpty, gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle) { score = 5 }
            else { return nil }

            let gotArtist = comparable(c.artistName)
            if !wantArtist.isEmpty, !gotArtist.isEmpty {
                if gotArtist == wantArtist { score += 8 }
                else if gotArtist.contains(wantArtist) || wantArtist.contains(gotArtist) { score += 4 }
                else { score -= 6 }
            }
            if let duration, duration > 0, let got = c.duration, got > 0 {
                let off = abs(got - duration)
                if off <= 3 { score += 6 } else if off > 15 { score -= 10 }
            }
            if !c.syncedLyrics.isEmpty { score += 3 }
            return score
        }

        return candidates
            .compactMap { c in score(c).map { (c, $0) } }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
    }

    // MARK: - Text

    /// What is sent to the search: accents and the replacement character removed.
    static func searchText(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// For comparing names: search text, lower-cased, with runs of spaces collapsed.
    static func comparable(_ string: String) -> String {
        searchText(string).lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The cache key for a track.
    static func cacheKey(title: String, artist: String) -> String {
        comparable(title) + "|" + comparable(artist)
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
