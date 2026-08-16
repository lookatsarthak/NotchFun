//
//  ClipboardAccessibility.swift
//  boringNotch
//

import ApplicationServices
import Foundation

/// Accessibility trust for the clipboard feature.
///
/// Deliberately checks trust **in this process**, not through `BoringNotchXPCHelper`.
/// The helper is a separate process with its own bundle identifier
/// (`io.github.lookatsarthak.notchfun.XPCHelper`), so `AXIsProcessTrusted()` there
/// reports whether *the helper* is trusted — which is not what granting the app
/// in System Settings gives you, and not what matters here either: the paste event and
/// the keyboard tap both come from the main app, so the main app is what must be
/// trusted.
///
/// Using the helper's answer made the app re-prompt on every single selection while
/// never becoming authorised.
@MainActor
enum ClipboardAccessibility {

    /// Whether this process may post events and run an event tap.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    private static var hasPromptedThisSession = false

    /// Shows the system prompt, but at most once per launch.
    ///
    /// Repeatedly prompting is worse than useless: the dialog only ever says "open
    /// System Settings", and a user who declined once should not be nagged on every
    /// click. Settings has an explicit button for a deliberate retry.
    static func promptOnceIfNeeded() {
        guard !hasPromptedThisSession, !isTrusted else { return }
        hasPromptedThisSession = true
        prompt()
    }

    /// Unconditional prompt, for an explicit user action such as the Settings button.
    static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
