//
//  MediaControllerProtocol.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import AppKit
import Combine

/// Main-actor bound, because that is what these already are: every conformer publishes
/// `@Published` state that SwiftUI reads on the main actor, and each was hopping to
/// `MainActor.run` by hand to update it. Stating it on the protocol lets the conformers
/// drop those hops, and stops `self` being captured in `@Sendable` closures it was never
/// safe to cross a thread with.
@MainActor
protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var supportsVolumeControl: Bool { get }
    var supportsFavorite: Bool { get }
    
    func setFavorite(_ favorite: Bool) async
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func setVolume(_ level: Double) async
    func isActive() -> Bool
    func updatePlaybackInfo() async
}
