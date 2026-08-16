//
//  ClipboardKeyEvent.swift
//  boringNotch
//

import Carbon.HIToolbox
import Foundation

/// A keystroke the clipboard tab claims while it is on screen.
///
/// Anything not represented here is passed through to the frontmost app untouched.
enum ClipboardKeyEvent: Equatable, Sendable {
    case character(String)
    case backspace
    case deleteWord
    case clearSearch
    case moveUp
    case moveDown
    case moveToTop
    case moveToBottom
    case pageUp
    case pageDown
    case confirm
    case cancel
    /// Command-1 through Command-9.
    case quickSelect(Int)
}

enum ClipboardKeyCodes {
    static let returnKey = CGKeyCode(kVK_Return)
    static let keypadEnter = CGKeyCode(kVK_ANSI_KeypadEnter)
    static let escape = CGKeyCode(kVK_Escape)
    static let delete = CGKeyCode(kVK_Delete)
    static let tab = CGKeyCode(kVK_Tab)
    static let upArrow = CGKeyCode(kVK_UpArrow)
    static let downArrow = CGKeyCode(kVK_DownArrow)
    static let leftArrow = CGKeyCode(kVK_LeftArrow)
    static let rightArrow = CGKeyCode(kVK_RightArrow)
    static let home = CGKeyCode(kVK_Home)
    static let end = CGKeyCode(kVK_End)
    static let pageUp = CGKeyCode(kVK_PageUp)
    static let pageDown = CGKeyCode(kVK_PageDown)

    /// Number-row 1…9, in order, for the Command-N quick-select shortcuts.
    static let digits: [CGKeyCode] = [
        CGKeyCode(kVK_ANSI_1), CGKeyCode(kVK_ANSI_2), CGKeyCode(kVK_ANSI_3),
        CGKeyCode(kVK_ANSI_4), CGKeyCode(kVK_ANSI_5), CGKeyCode(kVK_ANSI_6),
        CGKeyCode(kVK_ANSI_7), CGKeyCode(kVK_ANSI_8), CGKeyCode(kVK_ANSI_9)
    ]

    static let h = CGKeyCode(kVK_ANSI_H)
    static let u = CGKeyCode(kVK_ANSI_U)
    static let w = CGKeyCode(kVK_ANSI_W)
    static let n = CGKeyCode(kVK_ANSI_N)
    static let p = CGKeyCode(kVK_ANSI_P)
}
