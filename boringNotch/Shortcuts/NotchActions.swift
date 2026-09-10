//
//  NotchActions.swift
//  boringNotch
//

import AppKit
import Defaults
import Foundation

/// Everything the notch can be asked to do from outside its own UI.
///
/// These bodies used to live as closures inside `setupKeyboardShortcuts`, which meant a
/// keyboard shortcut was the only way to reach them — a closure on the app delegate is
/// not callable from an App Intent, which has no delegate reference. Both callers now go
/// through here, so a shortcut and its matching Shortcuts action cannot drift apart.
///
/// Deliberately free of AppIntents: `NotchAppIntents.swift` is the only file in the
/// project that imports it, which keeps the framework out of every target that does not
/// need it.
@MainActor
enum NotchActions {

    /// What a caller wants a two-state feature to end up as. Shortcuts users mostly want
    /// "on" or "off" so an automation is idempotent; a hotkey only ever wants "toggle".
    enum DesiredState {
        case on
        case off
        case toggle

        func resolve(current: Bool) -> Bool {
            switch self {
            case .on: return true
            case .off: return false
            case .toggle: return !current
            }
        }
    }

    /// Not `NSApp.delegate as? AppDelegate` — under SwiftUI's
    /// `@NSApplicationDelegateAdaptor` that cast returns nil, which made every action
    /// here a silent no-op.
    private static var appDelegate: AppDelegate? {
        AppDelegate.shared
    }

    // MARK: Notch

    /// The notch view model for the display the pointer is on, falling back to the
    /// primary one when multi-display mode is off.
    ///
    /// Lives here rather than on the app delegate because intents need it too. The
    /// `toggleNotchOpen` handler used to inline a second copy of this logic.
    static func viewModelForMouseLocation() -> BoringViewModel? {
        guard let delegate = appDelegate else { return nil }
        guard Defaults[.showOnAllDisplays] else { return delegate.vm }
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
            if let uuid = screen.displayUUID, let screenViewModel = delegate.viewModels[uuid] {
                return screenViewModel
            }
        }
        return delegate.vm
    }

    /// Open the notch, optionally on a given tab.
    ///
    /// `autoClose` is what the plain toggle shortcut wants — glance at it and let it go
    /// away. Anything that puts the user in front of a list to read from wants it off.
    static func openNotch(tab: NotchViews? = nil, autoClose: Bool) {
        guard let delegate = appDelegate, let viewModel = viewModelForMouseLocation() else { return }

        delegate.closeNotchTask?.cancel()
        delegate.closeNotchTask = nil

        if let tab { BoringViewCoordinator.shared.currentView = tab }
        viewModel.open()

        guard autoClose else { return }
        delegate.closeNotchTask = Task { [weak viewModel] in
            do {
                try await Task.sleep(for: .seconds(3))
                await MainActor.run { viewModel?.close() }
            } catch {}
        }
    }

    /// Forced, because every caller here is an explicit user action and must win over a
    /// feature holding the notch open.
    static func closeNotch() {
        guard let delegate = appDelegate, let viewModel = viewModelForMouseLocation() else { return }
        delegate.closeNotchTask?.cancel()
        delegate.closeNotchTask = nil
        viewModel.close(force: true)
    }

    static func toggleNotchOpen() {
        guard let viewModel = viewModelForMouseLocation() else { return }
        switch viewModel.notchState {
        case .closed: openNotch(autoClose: true)
        case .open: closeNotch()
        }
    }

    // MARK: Caffeine

    /// Returns whether caffeine is on afterwards.
    @discardableResult
    static func setCaffeine(_ desired: DesiredState, duration: CaffeineDuration? = nil) -> Bool {
        let manager = CaffeineManager.shared
        let wanted = desired.resolve(current: manager.isActive)
        guard wanted != manager.isActive || duration != nil else { return manager.isActive }

        if wanted {
            // The return value reports whether the power assertion was actually taken;
            // `isActive` below is the truth either way, so a failed assertion reads back
            // as "off" rather than as a lie.
            _ = manager.activate(
                mode: Defaults[.caffeineMode],
                duration: duration ?? Defaults[.caffeineDefaultDuration]
            )
        } else {
            manager.deactivate()
        }
        return manager.isActive
    }

    // MARK: Clipboard

    /// Paste what is already on the clipboard, without its formatting.
    ///
    /// Reads the pasteboard rather than the history, so it works with history switched
    /// off. Returns false when there is nothing to paste or Accessibility is not granted.
    @discardableResult
    static func pasteAsPlainText() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return false
        }
        guard ClipboardPasteService.ensureAuthorized(promptIfNeeded: true) else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: .fromNotchFun)
        ClipboardMonitor.shared.acknowledgeSelfCopy()
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            ClipboardPasteService.paste()
        }
        return true
    }

    /// Returns false when clipboard history is switched off, so a caller can say so
    /// rather than silently doing nothing.
    @discardableResult
    static func toggleClipboardPanel() -> Bool {
        guard Defaults[.clipboardHistoryEnabled] else { return false }
        guard let viewModel = viewModelForMouseLocation() else { return false }

        if viewModel.notchState == .open && BoringViewCoordinator.shared.currentView == .clipboard {
            closeNotch()
        } else {
            // Unlike the plain open shortcut, this must not auto-close after a few
            // seconds - the user is about to read and pick from a list.
            openNotch(tab: .clipboard, autoClose: false)
        }
        return true
    }

    /// `ClipboardStateViewModel` watches this key through `Defaults.updates`, so writing
    /// it is all that is needed to start or stop monitoring.
    @discardableResult
    static func setClipboardHistory(_ desired: DesiredState) -> Bool {
        let wanted = desired.resolve(current: Defaults[.clipboardHistoryEnabled])
        Defaults[.clipboardHistoryEnabled] = wanted
        return wanted
    }

    // MARK: Media

    static func toggleSneakPeek() {
        let coordinator = BoringViewCoordinator.shared
        if Defaults[.sneakPeekStyles] == .inline {
            coordinator.toggleExpandingView(status: !coordinator.expandingView.show, type: .music)
        } else {
            coordinator.toggleSneakPeek(
                status: !coordinator.sneakPeek.show,
                type: .music,
                duration: 3.0
            )
        }
    }

    // MARK: Keyboard backlight

    /// One sixteenth, which is the step the hardware brightness keys use.
    static let backlightStep: Float = 0.0625

    static func changeKeyboardBacklight(by delta: Float) {
        KeyboardBacklightManager.shared.setRelative(delta: delta)
    }
}
