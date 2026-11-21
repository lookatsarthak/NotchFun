//
//  BetterDisplayBridge.swift
//  NotchFun
//

import AppKit
import Defaults
import Foundation

/// Brightness on external displays through BetterDisplay, opt-in (Settings → Volume &
/// Brightness).
///
/// NotchFun doesn't drive BetterDisplay. While connected, brightness keys on an external
/// display pass through to BetterDisplay, which changes the display; BetterDisplay hides
/// its own pop-up and sends NotchFun its brightness events, and NotchFun shows its bar.
///
/// BetterDisplay's own pop-up settings are read and saved before they're changed, and
/// put back when the toggle goes off, when NotchFun quits, and on the next launch if
/// NotchFun didn't get to (a crash). Everything goes over distributed notifications with
/// no `userInfo`, which needs no permission and no entitlement. No reply within 3 s
/// means BetterDisplay isn't running or has integration switched off, and NotchFun keeps
/// to its own brightness handling.
@MainActor
@Observable
final class BetterDisplayBridge {
    static let shared = BetterDisplayBridge()

    /// Connected: BetterDisplay answered and its pop-up settings are NotchFun's.
    private(set) var isConnected = false

    /// Read by the media key interceptor, which may run off the main actor.
    nonisolated(unsafe) static var passesExternalBrightnessKeys = false

    private let center = DistributedNotificationCenter.default()
    private var pending: [String: (BetterDisplayProtocol.Response) -> Void] = [:]
    private var observers: [NSObjectProtocol] = []
    private var osdObserver: NSObjectProtocol?
    private var settingTask: Task<Void, Never>?

    private init() {}

    /// Called once at launch.
    func start() {
        observers.append(center.addObserver(forName: .init(BetterDisplayProtocol.responseName), object: nil, queue: .main) { [weak self] note in
            guard let string = note.object as? String else { return }
            MainActor.assumeIsolated { self?.received(string) }
        })
        observers.append(center.addObserver(forName: .init(BetterDisplayProtocol.launchedName), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if Defaults[.useBetterDisplay] { self?.connect() } }
        })
        observers.append(center.addObserver(forName: .init(BetterDisplayProtocol.terminatedName), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.markDisconnected() }
        })
        settingTask = Task { [weak self] in
            for await enabled in Defaults.updates(.useBetterDisplay) {
                guard let self else { return }
                if enabled { self.connect() } else { self.disconnect() }
            }
        }
    }

    /// Puts BetterDisplay's settings back synchronously, for app termination.
    func restoreOnQuit() {
        guard let saved = Defaults[.betterDisplaySavedOSD] else { return }
        for (setting, value) in saved { send(BetterDisplayProtocol.set(setting, to: value)) }
        Defaults[.betterDisplaySavedOSD] = nil
    }

    // MARK: - Connecting

    private func connect() {
        guard !isConnected else { return }
        var originals: [String: String] = [:]
        var answered = 0
        for setting in BetterDisplayProtocol.osdSettings {
            request(BetterDisplayProtocol.get(setting)) { [weak self] response in
                answered += 1
                if let value = BetterDisplayProtocol.settingValue(from: response.payload) { originals[setting] = value }
                guard answered == BetterDisplayProtocol.osdSettings.count else { return }
                self?.finishConnecting(originals: originals)
            }
        }
    }

    private func finishConnecting(originals: [String: String]) {
        guard Defaults[.useBetterDisplay], originals.count == BetterDisplayProtocol.osdSettings.count else { return }
        // Saved once. After a crash the saved values are still the user's, and what
        // BetterDisplay reports now are NotchFun's.
        if Defaults[.betterDisplaySavedOSD] == nil { Defaults[.betterDisplaySavedOSD] = originals }
        for (setting, value) in BetterDisplayProtocol.connectedValues { send(BetterDisplayProtocol.set(setting, to: value)) }
        osdObserver = center.addObserver(forName: .init(BetterDisplayProtocol.osdName), object: nil, queue: .main) { note in
            guard let string = note.object as? String,
                  let event = BetterDisplayProtocol.brightness(from: string) else { return }
            MainActor.assumeIsolated {
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(event.level))
            }
        }
        isConnected = true
        Self.passesExternalBrightnessKeys = true
    }

    private func disconnect() {
        if let saved = Defaults[.betterDisplaySavedOSD] {
            for (setting, value) in saved { send(BetterDisplayProtocol.set(setting, to: value)) }
            Defaults[.betterDisplaySavedOSD] = nil
        }
        markDisconnected()
    }

    private func markDisconnected() {
        if let osdObserver { center.removeObserver(osdObserver) }
        osdObserver = nil
        isConnected = false
        Self.passesExternalBrightnessKeys = false
    }

    // MARK: - Messages

    private func request(_ request: BetterDisplayProtocol.Request, reply: @escaping (BetterDisplayProtocol.Response) -> Void) {
        pending[request.uuid] = reply
        send(request)
        let uuid = request.uuid
        // No answer means no BetterDisplay, or integration off in it: drop the request.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.pending[uuid] = nil
        }
    }

    private func send(_ request: BetterDisplayProtocol.Request) {
        guard let json = BetterDisplayProtocol.encode(request) else { return }
        center.postNotificationName(.init(BetterDisplayProtocol.requestName), object: json, userInfo: nil, deliverImmediately: true)
    }

    private func received(_ string: String) {
        guard let response = BetterDisplayProtocol.decodeResponse(string), let uuid = response.uuid,
              let reply = pending.removeValue(forKey: uuid) else { return }
        reply(response)
    }
}

extension NSScreen {
    /// True for the Mac's own display.
    var isBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }
}
