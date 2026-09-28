//
//  FullscreenMediaDetection.swift
//  NotchFun
//
//  Created by Richard Kunkli on 06/09/2024.
//

import Foundation
import Combine
import Defaults
import MacroVisionKit

extension Notification.Name {
    /// Posted whenever the set of fullscreen spaces changes.
    ///
    /// Each notch has its own view model and each needs to re-evaluate, so this is a
    /// broadcast rather than a binding. It replaces a `@Published` dictionary that
    /// every view model reached into through a Combine projection.
    static let fullscreenStatusChanged = Notification.Name("fullscreenStatusChanged")
}

@MainActor
@Observable
final class FullscreenMediaDetector {
    static let shared = FullscreenMediaDetector()
    
    private(set) var fullscreenStatus: [String: Bool] = [:]

    /// The last set of spaces MacroVisionKit reported.
    ///
    /// Kept because the status depends on two more inputs that are not space changes —
    /// the hide setting and, under "media app only", which app is playing. Without it
    /// those could only take effect at the next space change: switch the setting while
    /// already in full screen, or start a video in the full-screen app, and nothing
    /// happened until you left full screen.
    @ObservationIgnored private var lastSpaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo] = []

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var settingTask: Task<Void, Never>?

    private init() {
        startMonitoring()
        observeSetting()
        observeMusicSource()
    }

    // No deinit. `init()` is private and `shared` is the only instance, so this lives
    // for the whole process; and under @Observable a mutable stored property cannot be
    // made nonisolated, which a deinit would need in order to touch it.

    private func startMonitoring() {
        monitorTask = Task { @MainActor in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                lastSpaces = spaces
                updateStatus()
            }
        }
    }

    private func observeSetting() {
        settingTask = Task { @MainActor [weak self] in
            for await _ in Defaults.updates(.hideNotchOption, initial: false) {
                self?.updateStatus()
            }
        }
    }

    /// `withObservationTracking` fires once per registration, so this re-arms itself.
    /// It only fires when the source app changes, not on every track or progress tick.
    private func observeMusicSource() {
        withObservationTracking {
            _ = MusicManager.shared.bundleIdentifier
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatus()
                self?.observeMusicSource()
            }
        }
    }

    private func updateStatus() {
        var newStatus: [String: Bool] = [:]

        for space in lastSpaces {
            if let uuid = space.screenUUID {
                let shouldDetect: Bool
                if Defaults[.hideNotchOption] == .nowPlayingOnly, let musicSourceBundle = MusicManager.shared.bundleIdentifier  {
                    shouldDetect = space.runningApps.contains(musicSourceBundle)
                } else {
                    shouldDetect = true
                }
                newStatus[uuid] = shouldDetect
            }
        }

        guard newStatus != fullscreenStatus else { return }
        self.fullscreenStatus = newStatus
        NotificationCenter.default.post(name: .fullscreenStatusChanged, object: nil)
    }
}

