//
//  MusicManager.swift
//  NotchFun
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import Combine
import Defaults
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

/// Main-actor isolated, explicitly.
///
/// It always was in practice - every controller it drives conforms to the
/// @MainActor MediaControllerProtocol, and all its state feeds SwiftUI - but the
/// isolation was being inferred from an @ObservedObject stored property rather than
/// stated. Removing that wrapper removed the inference, so it is written down now.
@MainActor
@Observable
class MusicManager {
    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()
    /// The launch-time deprecation check, kept so callers can wait for its answer.
    @ObservationIgnored private var deprecationCheck: Task<Bool, Never>?

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Published properties for UI
    var songTitle: String = "I'm Handsome"
    var artistName: String = "Me"
    var albumArt: NSImage = defaultImage
    var isPlaying = false
    var album: String = "Self Love"
    var isPlayerIdle: Bool = true
    var avgColor: NSColor = .white
    var bundleIdentifier: String? = nil
    var songDuration: TimeInterval = 0
    var elapsedTime: TimeInterval = 0
    var timestampDate: Date = .init()
    var playbackRate: Double = 1
    var isShuffled: Bool = false
    var repeatMode: RepeatMode = .off
    var volume: Double = 0.5
    var volumeControlSupported: Bool = true
    /// Plain reference. @ObservedObject does nothing outside a View, and it collides
    /// with the storage @Observable synthesises.
    let coordinator = BoringViewCoordinator.shared
    var usingAppIconForArtwork: Bool = false
    var currentLyrics: String = ""
    var isFetchingLyrics: Bool = false
    var syncedLyrics: [LyricLine] = []
    var canFavoriteTrack: Bool = false
    var isFavoriteTrack: Bool = false

    private var artworkData: Data? = nil

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    private init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Turning lyrics on mid-song should show them now, not from the next track.
        Defaults.publisher(.enableLyrics, options: [])
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self else { return }
                    self.lyricsTrackKey = nil
                    if change.newValue {
                        self.fetchLyricsIfAvailable(bundleIdentifier: self.bundleIdentifier, title: self.songTitle,
                                                    artist: self.artistName, duration: self.songDuration)
                    } else {
                        self.clearLyrics()
                    }
                }
            }
            .store(in: &cancellables)

        // Initialize deprecation check asynchronously
        deprecationCheck = Task { @MainActor in
            do {
                // Only probe when the cache cannot answer. See MediaChecker for why the
                // key is the OS build plus this app's build.
                if let cached = self.mediaChecker.cachedDeprecationStatus() {
                    self.isNowPlayingDeprecated = cached
                } else {
                    let result = try await MediaChecker.confirmedDeprecation {
                        try await self.mediaChecker.checkDeprecationStatus()
                    }
                    self.mediaChecker.cacheDeprecationStatus(result)
                    self.isNowPlayingDeprecated = result
                }
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Initialize the active controller after deprecation check
            self.setActiveControllerBasedOnPreference()
            self.observeControllerAppLifecycle()
            return self.isNowPlayingDeprecated
        }
    }

    /// Whether Now Playing is deprecated, once the launch-time check has answered.
    ///
    /// `isNowPlayingDeprecated` reads false until then, and the check runs in a Task,
    /// so it cannot have answered by the time applicationDidFinishLaunching reads it.
    /// That is how the "choose a media source" prompt, which launch gated on it, could
    /// never appear. Anything deciding at launch must wait on this instead.
    func nowPlayingDeprecation() async -> Bool {
        await deprecationCheck?.value ?? isNowPlayingDeprecated
    }

    // No deinit. `destroy()` is main-actor work - it tears down controllers and
    // observers - and deinit is nonisolated, so it cannot call it. That is not a loss:
    // `init()` is private, so `shared` is the only instance and it lives for the whole
    // process, and applicationWillTerminate already calls destroy() explicitly.
    
    public func destroy() {
        debounceIdleTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

        // Stop the Now Playing helper explicitly; releasing the controller is not enough.
        // See NowPlayingController.stopHelper().
        (activeController as? NowPlayingController)?.stopHelper()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    /// The app a controller needs in order to report anything, or nil if it needs none.
    ///
    /// Now Playing reads from the system, so it works whatever is running. The others
    /// drive a specific application and are inert without it.
    private func requiredBundleID(for type: MediaControllerType) -> String? {
        switch type {
        case .nowPlaying: return nil
        case .appleMusic: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        // A controller whose app is not running can never report anything, and the notch
        // sits on its placeholder track forever with nothing to say why. Every controller
        // has implemented `isActive()` all along; nothing consulted it when choosing one.
        //
        // The preference is deliberately not rewritten. The app may be launched later, and
        // the observer below switches to it when that happens.
        if let controller = createController(for: controllerType), controller.isActive() {
            setActiveController(controller)
            return
        }

        // Now Playing, not Apple Music, is the right place to land: it is the only source
        // that works regardless of what is installed, and it covers browsers - which is
        // where anyone who picked a per-app source for a web player was listening anyway.
        if !isNowPlayingDeprecated, let fallback = createController(for: .nowPlaying) {
            print("Media controller \(controllerType) is not running; using Now Playing")
            setActiveController(fallback)
        } else if let fallback = createController(for: .appleMusic) {
            setActiveController(fallback)
        }
    }

    /// Re-picks the controller when the app a preference depends on comes or goes.
    ///
    /// Without this the fallback above would be permanent for the session: launch Spotify
    /// after the notch, and it would stay on Now Playing until the next restart.
    private func observeControllerAppLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    let bundleID = app.bundleIdentifier
                else { return }
                Task { @MainActor in
                    guard let self else { return }
                    // Only the app the preference actually depends on, so an unrelated
                    // launch does not rebuild the controller.
                    guard bundleID == self.requiredBundleID(for: Defaults[.mediaController]) else { return }
                    self.setActiveControllerBasedOnPreference()
                }
            }
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Cancel any existing flip animation
        flipWorkItem?.cancel()

        // Set new active controller
        activeController = controller
        
        self.canFavoriteTrack = controller.supportsFavorite

        // Get current state from active controller
        forceUpdate()
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            withAnimation(NotchMotion.content) {
                self.isPlaying = state.isPlaying
                self.updateIdleState(state: state.isPlaying)
            }

            if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

        // Handle artwork and visual transitions for changed content
        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
                // Try to use app icon if no artwork but track changed
                if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                } else {
                    // Without this the previous track's artwork stayed up under the new title.
                    // (From upstream boring.notch 148532a.)
                    self.usingAppIconForArtwork = false
                    self.updateAlbumArt(newAlbumArt: defaultImage)
                }
            }
            self.artworkData = state.artwork

            if artworkChanged || state.artwork == nil {
                // Update last artwork change values
                self.lastArtworkTitle = state.title
                self.lastArtworkArtist = state.artist
                self.lastArtworkAlbum = state.album
                self.lastArtworkBundleIdentifier = state.bundleIdentifier
            }

            // Only update sneak peek if there's actual content and something changed
            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }

            // Fetch lyrics on content change
            self.fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title,
                                        artist: state.artist, duration: state.duration)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            // Update volume control support from active controller
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged {
            self.volume = state.volume
        }
        
        self.timestampDate = state.lastUpdated
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        // Toggle based on current state
        setFavorite(!isFavoriteTrack)
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    // MARK: - Lyrics
    //
    // Opt-in (Settings > Media), because finding them means asking lrclib.net about the
    // track. The pure parts (LRC, choosing a result, the line being sung) are in Lyrics.swift.

    /// The track the current or last lookup was for. A reply for any other track is dropped,
    /// and a second "content changed" for the same track (artwork usually arrives after the
    /// title) doesn't start another lookup.
    private var lyricsTrackKey: String?
    private var lyricsTask: Task<Void, Never>?
    /// Small and evictable: a replayed or skipped-back track shows its lyrics at once.
    private let lyricsCache: NSCache<NSString, LyricsCacheEntry> = {
        let cache = NSCache<NSString, LyricsCacheEntry>()
        cache.countLimit = 50
        return cache
    }()

    private final class LyricsCacheEntry {
        let plain: String
        let synced: [LyricLine]
        init(plain: String, synced: [LyricLine]) { self.plain = plain; self.synced = synced }
    }

    private func clearLyrics() {
        lyricsTask?.cancel()
        lyricsTask = nil
        isFetchingLyrics = false
        currentLyrics = ""
        syncedLyrics = []
    }

    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String, duration: Double) {
        guard Defaults[.enableLyrics], !title.isEmpty else {
            lyricsTrackKey = nil
            clearLyrics()
            return
        }
        let key = Lyrics.cacheKey(title: title, artist: artist)
        guard key != lyricsTrackKey else { return }
        lyricsTrackKey = key
        lyricsTask?.cancel()

        if let cached = lyricsCache.object(forKey: key as NSString) {
            isFetchingLyrics = false
            currentLyrics = cached.plain
            syncedLyrics = cached.synced
            return
        }

        isFetchingLyrics = true
        currentLyrics = ""
        syncedLyrics = []
        lyricsTask = Task { @MainActor [weak self] in
            // Synced lyrics first, even for Apple Music: its own lyrics are plain text, and a
            // line that follows the song is the point of the feature. Apple Music's are the
            // fallback when the web has nothing.
            let web = await Self.lyricsFromWeb(title: title, artist: artist, duration: duration)
            guard let self, !Task.isCancelled, self.lyricsTrackKey == key else { return }
            var plain = web?.plainLyrics ?? ""
            var synced = web.map { Lyrics.parseLRC($0.syncedLyrics) } ?? []
            if synced.isEmpty, bundleIdentifier?.contains("com.apple.Music") == true,
               let native = await Self.appleMusicLyrics() {
                guard !Task.isCancelled, self.lyricsTrackKey == key else { return }
                plain = native
                synced = []
            }
            if plain.isEmpty, let first = synced.first { plain = first.text }
            self.currentLyrics = plain
            self.syncedLyrics = synced
            self.isFetchingLyrics = false
            self.lyricsCache.setObject(LyricsCacheEntry(plain: plain, synced: synced), forKey: key as NSString)
        }
    }

    /// Searches lrclib.net, by title and artist and then by title alone, and returns the
    /// result that matches this track, if any does.
    private static func lyricsFromWeb(title: String, artist: String, duration: Double) async -> Lyrics.Candidate? {
        let searchTitle = Lyrics.searchText(title)
        let searchArtist = Lyrics.searchText(artist)
        var queries: [[URLQueryItem]] = []
        if !searchArtist.isEmpty {
            queries.append([URLQueryItem(name: "track_name", value: searchTitle), URLQueryItem(name: "artist_name", value: searchArtist)])
        }
        queries.append([URLQueryItem(name: "track_name", value: searchTitle)])

        for query in queries {
            guard !Task.isCancelled else { return nil }
            var components = URLComponents(string: "https://lrclib.net/api/search")
            components?.queryItems = query
            guard let url = components?.url else { continue }
            var request = URLRequest(url: url)
            // The line under the title says "Loading lyrics..." meanwhile; a minute was too long.
            request.timeoutInterval = 10
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { continue }
            let candidates = json.compactMap(Lyrics.Candidate.init(json:))
            if let match = Lyrics.bestMatch(in: candidates, title: title, artist: artist, duration: duration) {
                return match
            }
        }
        return nil
    }

    /// The current track's lyrics from the Music app, when it has some.
    private static func appleMusicLyrics() async -> String? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else { return nil }
        let script = """
        tell application "Music"
            if it is running then
                if player state is playing or player state is paused then
                    try
                        set l to lyrics of current track
                        if l is missing value then return ""
                        return l
                    on error
                        return ""
                    end try
                end if
            end if
            return ""
        end tell
        """
        guard let result = try? await AppleScriptHelper.execute(script),
              let lyrics = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lyrics.isEmpty else { return nil }
        return lyrics
    }

    /// The line being sung at `elapsed`: empty before the first line starts, the plain
    /// lyrics when there are no timings.
    #if NOTCHFUN_SOAK
    /// Invented synced lyrics, one line every 3 s from the current position, for testing.
    func showDemoLyrics() {
        let start = elapsed(at: Date())
        let lines = ["the city hums a quiet tune", "and every window holds a light",
                     "we walk until the morning comes", "and call the empty streets our own",
                     "the city hums a quiet tune", "and every window holds a light"]
        syncedLyrics = lines.enumerated().map { LyricLine(time: start + 1 + Double($0.offset) * 3, text: $0.element) }
    }
    #endif

    /// When the shown lyric line next changes: now, then each upcoming line start on the
    /// playback clock. For a TimelineView, so lyrics redraw once per line and at no other
    /// time. Just now while paused or without synced lyrics.
    func lyricRedrawDates(now: Date = Date()) -> [Date] {
        guard isPlaying, !syncedLyrics.isEmpty else { return [now] }
        let elapsed = elapsedTime + now.timeIntervalSince(timestampDate) * playbackRate
        return [now] + Lyrics.upcomingLineDates(
            after: elapsed, in: syncedLyrics,
            clockDate: timestampDate, clockElapsed: elapsedTime, rate: playbackRate)
    }

    /// The playback position at `date`, following the clock while playing.
    func elapsed(at date: Date) -> Double {
        guard isPlaying else { return elapsedTime }
        let progressed = elapsedTime + date.timeIntervalSince(timestampDate) * playbackRate
        return min(max(progressed, 0), songDuration)
    }

    func lyricLine(at elapsed: Double) -> String {
        guard !syncedLyrics.isEmpty else { return currentLyrics }
        return Lyrics.lineIndex(at: elapsed, in: syncedLyrics).map { syncedLyrics[$0].text } ?? ""
    }

    private func triggerFlipAnimation() {
        // Cancel any existing animation
        flipWorkItem?.cancel()

        // Create a new animation
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }

        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation(NotchMotion.content) {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        withAnimation(NotchMotion.content) {
            self.albumArt = newAlbumArt
            if Defaults[.coloredSpectrogram] {
                self.calculateAverageColor()
            }
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(NotchMotion.content) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        Task {
            await activeController?.togglePlay()
        }
    }

    /// A two-finger swipe on the music: left for the next track, right for the previous,
    /// with a tick on the trackpad.
    func skip(_ swipe: HorizontalSwipeDetector.Swipe) {
        switch swipe {
        case .next: nextTrack()
        case .previous: previousTrack()
        }
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                await self?.activeController?.updatePlaybackInfo()
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
        // Check if bundle identifier is valid and if the app is actually running
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }
        
        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            // For unsupported apps, don't sync volume
            return
        }
        
        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript) {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0
            
            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}
