//
//  LyricsTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Lyrics: reading LRC")
struct LyricsParsingTests {

    @Test("One, two or three fraction digits mean tenths, hundredths, thousandths")
    func fractionDigits() {
        let lines = Lyrics.parseLRC("[00:01.5] a\n[00:02.25] b\n[00:03.125] c\n[00:04] d")
        #expect(lines.map(\.time) == [1.5, 2.25, 3.125, 4])
        #expect(lines.map(\.text) == ["a", "b", "c", "d"])
    }

    @Test("A line with several stamps is sung at each of them")
    func repeatedLine() {
        let lines = Lyrics.parseLRC("[00:10.00][01:20.00] chorus\n[00:30.00] verse")
        #expect(lines == [LyricLine(time: 10, text: "chorus"), LyricLine(time: 30, text: "verse"),
                          LyricLine(time: 80, text: "chorus")])
    }

    @Test("Tags, empty lines and stamp-only lines are skipped")
    func skipsNonLyrics() {
        let lrc = "[ar: Someone]\n[ti: Song]\n\n[00:05.00]\n[00:06.00]   \n[00:07.00] words"
        #expect(Lyrics.parseLRC(lrc) == [LyricLine(time: 7, text: "words")])
    }

    @Test("Long tracks: three-digit minutes, and lines come out sorted")
    func longAndUnsorted() {
        let lines = Lyrics.parseLRC("[100:00.00] late\n[00:01.00] early")
        #expect(lines.map(\.time) == [1, 6000])
    }

    @Test("Malformed stamps are not lyrics", arguments: ["[0:5.00] x", "[00:61.00] x", "[aa:00.00] x", "[00:00.1234] x", "no stamp"])
    func malformed(line: String) {
        #expect(Lyrics.parseLRC(line).isEmpty)
    }

    @Test("Windows line endings")
    func crlf() {
        #expect(Lyrics.parseLRC("[00:01.00] a\r\n[00:02.00] b\r\n").map(\.text) == ["a", "b"])
    }
}

@Suite("Lyrics: the line being sung")
struct LyricsTimingTests {
    let lines = [LyricLine(time: 5, text: "one"), LyricLine(time: 10, text: "two"), LyricLine(time: 15, text: "three")]

    @Test("Nothing before the first line, then each line from its start")
    func lineAtTime() {
        #expect(Lyrics.lineIndex(at: 0, in: lines) == nil)
        #expect(Lyrics.lineIndex(at: 4.99, in: lines) == nil)
        #expect(Lyrics.lineIndex(at: 5, in: lines) == 0)
        #expect(Lyrics.lineIndex(at: 9.99, in: lines) == 0)
        #expect(Lyrics.lineIndex(at: 10, in: lines) == 1)
        #expect(Lyrics.lineIndex(at: 999, in: lines) == 2)
        #expect(Lyrics.lineIndex(at: 1, in: []) == nil)
    }

    @Test("Redraw dates are the upcoming line starts on the playback clock")
    func redrawDates() {
        let clock = Date(timeIntervalSinceReferenceDate: 1000)
        let dates = Lyrics.upcomingLineDates(after: 7, in: lines, clockDate: clock, clockElapsed: 6, rate: 1)
        #expect(dates == [clock.addingTimeInterval(4), clock.addingTimeInterval(9)])
        let fast = Lyrics.upcomingLineDates(after: 7, in: lines, clockDate: clock, clockElapsed: 6, rate: 2)
        #expect(fast == [clock.addingTimeInterval(2), clock.addingTimeInterval(4.5)])
        #expect(Lyrics.upcomingLineDates(after: 7, in: lines, clockDate: clock, clockElapsed: 6, rate: 0).isEmpty)
    }
}

@Suite("Lyrics: choosing the search result")
struct LyricsMatchTests {
    func candidate(_ title: String, _ artist: String, duration: Double? = 200, plain: String = "words", synced: String = "") -> Lyrics.Candidate {
        Lyrics.Candidate(trackName: title, artistName: artist, duration: duration, plainLyrics: plain, syncedLyrics: synced)
    }

    @Test("The first result is not taken when a later one is the track")
    func prefersRealMatch() {
        let results = [candidate("Yesterday (Live)", "A Cover Band"), candidate("Yesterday", "The Beatles")]
        #expect(Lyrics.bestMatch(in: results, title: "Yesterday", artist: "The Beatles", duration: 200)?.artistName == "The Beatles")
    }

    @Test("No result is better than another song's lyrics")
    func rejectsWrongSongs() {
        let results = [candidate("Something Else", "The Beatles")]
        #expect(Lyrics.bestMatch(in: results, title: "Yesterday", artist: "The Beatles", duration: 200) == nil)
    }

    @Test("A recording of a very different length loses to the right one")
    func durationDecides() {
        let results = [candidate("Song", "Artist", duration: 420, synced: "[00:01.00] x"),
                       candidate("Song", "Artist", duration: 201)]
        #expect(Lyrics.bestMatch(in: results, title: "Song", artist: "Artist", duration: 200)?.duration == 201)
    }

    @Test("Synced lyrics win a tie")
    func syncedWinsTie() {
        let results = [candidate("Song", "Artist"), candidate("Song", "Artist", synced: "[00:01.00] x")]
        #expect(Lyrics.bestMatch(in: results, title: "Song", artist: "Artist", duration: nil)?.syncedLyrics.isEmpty == false)
    }

    @Test("Results without lyrics are ignored")
    func ignoresEmpty() {
        let results = [candidate("Song", "Artist", plain: "", synced: "")]
        #expect(Lyrics.bestMatch(in: results, title: "Song", artist: "Artist", duration: 200) == nil)
    }

    @Test("Accents, case and spacing don't stop a match; a remaster suffix still matches")
    func normalisation() {
        #expect(Lyrics.bestMatch(in: [candidate("Café  del Mar", "ENERGY 52")], title: "cafe del mar", artist: "Energy 52", duration: 200) != nil)
        #expect(Lyrics.bestMatch(in: [candidate("Song", "Artist")], title: "Song - Remastered 2011", artist: "Artist", duration: 200) != nil)
    }

    @Test("Cache keys ignore accents, case and spacing")
    func cacheKey() {
        #expect(Lyrics.cacheKey(title: "Café  del Mar", artist: "Energy 52") == Lyrics.cacheKey(title: "cafe del mar", artist: "ENERGY 52"))
    }
}
