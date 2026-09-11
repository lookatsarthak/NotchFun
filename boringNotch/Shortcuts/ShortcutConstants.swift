//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel", initial: .init(.c, modifiers: [.shift, .command]))
    /// No defaults, for the same reason as `toggleCaffeine` below: ⌘F1 is macOS's own
    /// Mirror Displays toggle and ⌘F2 sits right beside it, so shipping either as a
    /// default would take a combination the system already owns. These two were declared
    /// with exactly those bindings for a year but had no handler and no settings UI —
    /// inert only because Swift statics are lazy and nothing referenced them.
    static let decreaseBacklight = Self("decreaseBacklight")
    static let increaseBacklight = Self("increaseBacklight")
    static let toggleSneakPeek = Self("toggleSneakPeek", initial: .init(.h, modifiers: [.command, .shift]))
    /// No default binding: every obvious combination is already taken by something, and
    /// silently stealing one from another app is worse than making the user pick.
    static let toggleCaffeine = Self("toggleCaffeine")
    /// Paste whatever is on the clipboard without its formatting.
    ///
    /// No default, like toggleCaffeine: shipping a binding for this would squat on a
    /// combination another app may already use, and ⌘⌥⇧V is popular precisely because
    /// several apps claim it.
    static let pasteAsPlainText = Self("pasteAsPlainText")
    static let toggleNotchOpen = Self("toggleNotchOpen", initial: .init(.i, modifiers: [.command, .shift]))
}
