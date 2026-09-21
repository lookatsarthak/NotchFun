//
//  AccessoryBatteryManager.swift
//  NotchFun
//

import CoreAudio
import Defaults
import Foundation
import SwiftUI

/// Tracks the battery of the Bluetooth accessory you are listening through.
///
/// There is no polling here and no timer. Two things ask for a reading:
///
/// - **A connect.** macOS switches `kAudioHardwarePropertyDefaultOutputDevice` to a pair
///   of earbuds the moment they connect, so one CoreAudio listener is the whole event
///   source. That is cheaper and far more reliable than the IOBluetooth connect
///   notifications — those are classic-Bluetooth API, unreliable for AACP accessories,
///   and would have had to live in the XPC helper, which cannot push events back and
///   which launchd may terminate under it.
/// - **Opening the notch**, so the header is not showing a stale number.
///
/// The notch opens on *hover*, so that second trigger is the dangerous one: without the
/// cache and the in-flight guard below, sweeping the pointer across the notch would spawn
/// a `system_profiler` per crossing.
///
/// Low battery is deliberately not handled. macOS Tahoe already shows its own AirPods
/// low-battery alert, and duplicating a system notification is worse than silence — it
/// would also have meant the only repeating timer in the app.
@MainActor
@Observable
final class AccessoryBatteryManager {
    static let shared = AccessoryBatteryManager()

    /// The accessory currently being listened through, if it reports a battery.
    ///
    /// `nil` covers three different things on purpose — nothing connected, connected but
    /// reporting no battery, and the helper being unreachable. None of them should render
    /// a number, and distinguishing them in the UI would be noise.
    private(set) var current: AccessoryBattery?

    /// How long a reading is treated as fresh. Battery moves by a percent every several
    /// minutes; a hover is not a reason to shell out again.
    private static let cacheLifetime: TimeInterval = 60

    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?
    private var listenerInstalled = false
    private var settingTask: Task<Void, Never>?

    private init() {}


    /// Called once at launch.
    func start() {
        guard !listenerInstalled else { return }
        listenerInstalled = true

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, nil
        ) { [weak self] _, _ in
            Task { @MainActor in self?.outputDeviceChanged() }
        }

        // Catch the case where earbuds were already connected when the app launched.
        refresh(force: true, announce: false)

        // And the case where they are already connected when the setting is switched on.
        // Without this, turning it on in Settings appears to do nothing: there is no
        // device change to listen for, so the first reading would not arrive until the
        // next time the notch happened to be opened.
        settingTask = Task { [weak self] in
            for await enabled in Defaults.updates(.showAccessoryBattery, initial: false) {
                guard let self else { return }
                if enabled {
                    self.refresh(force: true, announce: false)
                } else {
                    // Turned off: drop the reading so the header stops showing it at once.
                    if self.current != nil { self.current = nil }
                }
            }
        }
    }

    /// The notch is about to open — make sure the header is not showing a stale number.
    func refreshForNotchOpen() {
        refresh(force: false, announce: false)
    }

    private func outputDeviceChanged() {
        guard Defaults[.showAccessoryBattery] else {
            current = nil
            return
        }
        guard SystemAudioOutput.isBluetooth() else {
            // Switched back to speakers or a wired device: drop the reading rather than
            // leaving the last accessory's number in the header.
            //
            // Guarded on inequality because assigning to a fires
            // objectWillChange even when the value is unchanged, and this view model is
            // observed by ContentView - a no-op assignment is a free re-render of the
            // whole notch.
            if current != nil { current = nil }
            return
        }
        refresh(force: true, announce: true)
    }

    /// - Parameters:
    ///   - force: ignore the cache. True only for a real device change.
    ///   - announce: show the transient banner afterwards.
    private func refresh(force: Bool, announce: Bool) {
        guard Defaults[.showAccessoryBattery] else { return }

        // Nothing is connected over Bluetooth, so there is nothing to ask about and no
        // reason to spawn anything.
        guard SystemAudioOutput.isBluetooth() else {
            // Same inequality guard as above: a redundant publish re-renders the notch.
            if current != nil { current = nil }
            return
        }

        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < Self.cacheLifetime {
            return
        }

        // A hover storm must not become a process storm. One request at a time; later
        // callers ride on the one already running rather than starting another.
        guard inFlight == nil else { return }

        inFlight = Task { [weak self] in
            let data = await XPCHelperClient.shared.bluetoothProfileJSON()
            guard let self else { return }
            defer { self.inFlight = nil }
            guard !Task.isCancelled else { return }

            // A nil payload is "no answer", not "no battery". Keeping the previous
            // reading means a momentarily unreachable helper does not blank the header.
            guard let data else { return }

            self.lastFetch = Date()
            let readings = AccessoryBatteryParser.parse(data)
            let reading = self.matchOutputDevice(among: readings) ?? readings.first

            withAnimation(NotchMotion.content) {
                self.current = reading
            }

            if announce, reading != nil, Defaults[.showAccessoryBattery] {
                BoringViewCoordinator.shared.toggleExpandingView(
                    status: true, type: .accessoryBattery
                )
            }
        }
    }

    /// Prefer the accessory that is actually the audio output, so a paired mouse or
    /// keyboard cannot claim the banner.
    private func matchOutputDevice(among readings: [AccessoryBattery]) -> AccessoryBattery? {
        guard let name = SystemAudioOutput.name() else { return nil }
        return readings.first { $0.name == name }
    }

}
