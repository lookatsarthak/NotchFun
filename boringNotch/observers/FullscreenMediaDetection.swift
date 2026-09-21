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
    
    private var monitorTask: Task<Void, Never>?
    
    private init() {
        startMonitoring()
    }
    
    // No deinit. `init()` is private and `shared` is the only instance, so this lives
    // for the whole process; and under @Observable a mutable stored property cannot be
    // made nonisolated, which a deinit would need in order to touch it.
    
    private func startMonitoring() {
        monitorTask = Task { @MainActor in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                updateStatus(with: spaces)
            }
        }
    }
    
    private func updateStatus(with spaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo]) {
        var newStatus: [String: Bool] = [:]
        
        for space in spaces {
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

