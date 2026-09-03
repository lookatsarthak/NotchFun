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
    static let toggleMicrophone = Self("toggleMicrophone", initial: .init(.f5, modifiers: [.function]))
    static let decreaseBacklight = Self("decreaseBacklight", initial: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", initial: .init(.f2, modifiers: [.command]))
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
