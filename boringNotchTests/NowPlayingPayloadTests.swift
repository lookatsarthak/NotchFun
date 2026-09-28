//
//  NowPlayingPayloadTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Now Playing adapter lines")
struct NowPlayingPayloadTests {
    private func update(_ json: String) throws -> NowPlayingUpdate {
        try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(json.utf8))
    }

    /// A state that has been playing a titled track with artwork.
    private var playing: PlaybackState {
        var state = PlaybackState(bundleIdentifier: "com.apple.Safari")
        state.title = "Old Song"
        state.artist = "Old Artist"
        state.album = "Old Album"
        state.duration = 240
        state.artwork = Data([1, 2, 3])
        state.isPlaying = true
        return state
    }

    @Test("null and absent decode differently")
    func nullIsRecordedAsCleared() throws {
        let line = try update(#"{"diff":true,"payload":{"title":null,"playing":true}}"#)
        #expect(line.payload.title == nil)
        #expect(line.payload.cleared == [.title])
    }

    @Test("A diff that clears the title does not keep the previous track's title")
    func clearedTitleResets() throws {
        let next = playing.applying(
            try update(#"{"diff":true,"payload":{"title":null,"artist":null,"duration":null}}"#)
        )
        #expect(next.title == "")
        #expect(next.artist == "")
        #expect(next.duration == 0)
        #expect(next.album == "Old Album")
    }

    @Test("A diff that does not mention a key leaves it alone")
    func absentKeysCarryOver() throws {
        let next = playing.applying(try update(#"{"diff":true,"payload":{"playing":false}}"#))
        #expect(next.title == "Old Song")
        #expect(next.duration == 240)
        #expect(next.isPlaying == false)
    }

    @Test("Artwork survives a diff that does not mention it, and clears on null")
    func artwork() throws {
        let kept = playing.applying(try update(#"{"diff":true,"payload":{"playing":false}}"#))
        #expect(kept.artwork == Data([1, 2, 3]))

        let cleared = playing.applying(try update(#"{"diff":true,"payload":{"artworkData":null}}"#))
        #expect(cleared.artwork == nil)
    }

    @Test("A full line resets anything it leaves out")
    func fullLineResets() throws {
        let next = playing.applying(
            try update(#"{"diff":false,"payload":{"title":"New","bundleIdentifier":"company.thebrowser.Browser"}}"#)
        )
        #expect(next.title == "New")
        #expect(next.artist == "")
        #expect(next.artwork == nil)
        #expect(next.isPlaying == false)
        #expect(next.bundleIdentifier == "company.thebrowser.Browser")
    }

    @Test("The empty full line the adapter sends when nothing is playing")
    func emptyFullLine() throws {
        let next = playing.applying(try update(#"{"diff":false,"payload":{}}"#))
        #expect(next.title == "")
        #expect(next.isPlaying == false)
        #expect(next.bundleIdentifier == "")
    }

    @Test("Unknown keys the adapter adds do not break decoding")
    func unknownKeys() throws {
        let line = try update(
            #"{"diff":true,"payload":{"contentItemIdentifier":"ABC","uniqueIdentifier":769,"duration":8.07}}"#
        )
        #expect(line.payload.duration == 8.07)
        #expect(line.payload.cleared.isEmpty)
    }
}
