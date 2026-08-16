//
//  ClipboardPasteService.swift
//  boringNotch
//
//  Adapted from Maccy (https://github.com/p0deje/Maccy), Maccy/Clipboard.swift,
//  which credits Clipy for the original approach.
//  MIT License © Alex Rodionov. See THIRD_PARTY_LICENSES.
//

import AppKit
import Carbon.HIToolbox
import Defaults
import Foundation
import os

/// Synthesises Command-V into whatever app is frontmost.
///
/// Posting keyboard events requires the Accessibility (post-events) TCC grant. The
/// app already obtains that through its non-sandboxed XPC helper for the HUD
/// replacement, so this reuses the same plumbing rather than adding a second
/// permission flow.
///
/// Note the grant is tied to the signed binary, so it resets on every unsigned
/// rebuild during development — a denied paste in a dev build is usually this and not
/// a bug in the code.
@MainActor
enum ClipboardPasteService {

    private static let logger = Logger(subsystem: "io.github.lookatsarthak.notchfun", category: "ClipboardPaste")

    /// Whether pasting is currently possible, without prompting.
    static var isAuthorized: Bool { ClipboardAccessibility.isTrusted }

    /// Asks for Accessibility if needed. Returns whether pasting may proceed.
    @discardableResult
    static func ensureAuthorized(promptIfNeeded: Bool) -> Bool {
        if ClipboardAccessibility.isTrusted { return true }
        if promptIfNeeded { ClipboardAccessibility.promptOnceIfNeeded() }
        return false
    }

    /// Posts Command-V to the session event tap.
    ///
    /// Three details here are load-bearing and were all learned the hard way upstream:
    ///  - the extra `0x000008` flag bit marks a left/right modifier as pressed, without
    ///    which some apps ignore the synthetic Command (Flycut #18);
    ///  - the event-suppression filter has to permit local mouse and system events, or
    ///    the user's own input is swallowed for the suppression interval;
    ///  - the key code is configurable, because on Dvorak-QWERTY⌘ layouts the physical
    ///    "v" key is not virtual key 9 (Maccy #482).
    static func paste() {
        let keyCode = CGKeyCode(UInt16(max(0, Defaults[.clipboardPasteKeyCode])))

        // .maskCommand plus the left/right-modifier bit.
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0000_0008)

        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            logger.error("Failed to create paste key events")
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    /// Default key code for the ANSI "v" key.
    static var defaultPasteKeyCode: Int { Int(kVK_ANSI_V) }
}
