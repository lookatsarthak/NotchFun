//
//  NowPlayingPayload.swift
//  NotchFun
//

import Foundation

/// One line of the MediaRemote adapter's `stream` output.
///
/// Foundation only, so it compiles into the standalone test bundle.
struct NowPlayingUpdate: Decodable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

/// The adapter's payload, which in diff mode has three states per key, not two:
///
/// - **absent** — unchanged since the last line;
/// - **a value** — changed to that value;
/// - **`null`** — the value went away (the new track has no title, no artwork, no
///   duration…).
///
/// A plain `String?` folds the last two into `nil`, which is how a track with no title
/// used to inherit the previous track's title. `cleared` keeps the distinction.
struct NowPlayingPayload: Decodable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let volume: Double?

    /// Keys sent as an explicit `null`.
    let cleared: Set<Key>

    enum Key: String, CodingKey, CaseIterable {
        case title, artist, album, duration, elapsedTime, shuffleMode, repeatMode
        case artworkData, timestamp, playbackRate, playing
        case parentApplicationBundleIdentifier, bundleIdentifier, volume
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        album = try c.decodeIfPresent(String.self, forKey: .album)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        elapsedTime = try c.decodeIfPresent(Double.self, forKey: .elapsedTime)
        shuffleMode = try c.decodeIfPresent(Int.self, forKey: .shuffleMode)
        repeatMode = try c.decodeIfPresent(Int.self, forKey: .repeatMode)
        artworkData = try c.decodeIfPresent(String.self, forKey: .artworkData)
        timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp)
        playbackRate = try c.decodeIfPresent(Double.self, forKey: .playbackRate)
        playing = try c.decodeIfPresent(Bool.self, forKey: .playing)
        parentApplicationBundleIdentifier = try c.decodeIfPresent(
            String.self, forKey: .parentApplicationBundleIdentifier)
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        volume = try c.decodeIfPresent(Double.self, forKey: .volume)
        cleared = Set(Key.allCases.filter { c.contains($0) && ((try? c.decodeNil(forKey: $0)) ?? false) })
    }
}

extension PlaybackState {
    /// The state after applying one adapter line.
    ///
    /// A full line (`diff` false or missing) describes the whole state, so anything it
    /// leaves out goes back to its default. A diff line only touches the keys it names;
    /// a key it names as `null` also goes back to its default.
    func applying(_ update: NowPlayingUpdate, now: Date = Date()) -> PlaybackState {
        let payload = update.payload
        let diff = update.diff ?? false

        /// The new value, the old one, or the default — in that order of preference.
        func pick<T>(_ value: T?, _ key: NowPlayingPayload.Key, old: T, reset: T) -> T {
            if let value { return value }
            return diff && !payload.cleared.contains(key) ? old : reset
        }

        var next = PlaybackState(bundleIdentifier: bundleIdentifier)

        next.title = pick(payload.title, .title, old: title, reset: "")
        next.artist = pick(payload.artist, .artist, old: artist, reset: "")
        next.album = pick(payload.album, .album, old: album, reset: "")
        next.duration = pick(payload.duration, .duration, old: duration, reset: 0)

        if let elapsedTime = payload.elapsedTime {
            next.currentTime = elapsedTime
        } else if diff, !payload.cleared.contains(.elapsedTime) {
            if payload.playing == false {
                // Paused by this line: advance to where playback actually stopped.
                next.currentTime = currentTime + playbackRate * now.timeIntervalSince(lastUpdated)
            } else {
                next.currentTime = currentTime
            }
        } else {
            next.currentTime = 0
        }

        next.isShuffled = pick(payload.shuffleMode.map { $0 != 1 }, .shuffleMode, old: isShuffled, reset: false)
        next.repeatMode = pick(
            payload.repeatMode.map { RepeatMode(rawValue: $0) ?? .off },
            .repeatMode, old: repeatMode, reset: .off
        )

        // Carried over on a diff that does not mention it. Dropping it there (as this used
        // to) only went unnoticed because MusicManager ignores a nil artwork unless the
        // track also changed.
        next.artwork = pick(
            payload.artworkData.map {
                Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            .artworkData, old: artwork, reset: nil
        )

        let stamp = payload.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) }
        next.lastUpdated = pick(stamp, .timestamp, old: lastUpdated, reset: now)

        next.playbackRate = pick(payload.playbackRate, .playbackRate, old: playbackRate, reset: 1)
        next.isPlaying = pick(payload.playing, .playing, old: isPlaying, reset: false)
        next.bundleIdentifier = payload.parentApplicationBundleIdentifier
            ?? payload.bundleIdentifier
            ?? (diff ? bundleIdentifier : "")
        next.volume = pick(payload.volume, .volume, old: volume, reset: 0.5)

        return next
    }
}
