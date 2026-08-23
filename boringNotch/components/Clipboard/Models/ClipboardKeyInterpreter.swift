//
//  ClipboardKeyInterpreter.swift
//  boringNotch
//

import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Decides whether a keystroke belongs to the clipboard panel.
///
/// Kept separate from `ClipboardKeyCaptureService` — and free of any dependency on the
/// tap, the view, or `Defaults` — because this is the piece that determines what gets
/// taken away from the frontmost app. It needs to be readable and testable on its own.
enum ClipboardKeyInterpreter {

    /// - Returns: the action to perform, or `nil` to let the event through untouched.
    ///
    /// Anything with Command held passes through except Command-1…9, so system and app
    /// shortcuts — Command-Q above all — always keep working. That is the escape hatch
    /// if anything here ever misbehaves.
    static func interpret(keyCode: CGKeyCode, flags: CGEventFlags, text: @autoclosure () -> String?) -> ClipboardKeyEvent? {
        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)
        let option = flags.contains(.maskAlternate)

        if command {
            guard !control, !option, let index = ClipboardKeyCodes.digits.firstIndex(of: keyCode) else {
                return nil
            }
            return .quickSelect(index + 1)
        }

        if control {
            // A few readline-style bindings, matching what Maccy offers.
            switch keyCode {
            case ClipboardKeyCodes.h: return .backspace
            case ClipboardKeyCodes.u: return .clearSearch
            case ClipboardKeyCodes.w: return .deleteWord
            case ClipboardKeyCodes.n: return .moveDown
            case ClipboardKeyCodes.p: return .moveUp
            default: return nil
            }
        }

        // Return is handled before the option guard below, not inside the switch after
        // it. Option pastes without formatting, and that guard returns nil for every
        // option combo - so with the case sitting after it, option-Return was
        // unreachable and the plain-text paste could never fire.
        switch keyCode {
        case ClipboardKeyCodes.returnKey, ClipboardKeyCodes.keypadEnter:
            return option ? .confirmAsPlainText : .confirm
        default:
            break
        }

        // Every other option combo belongs to the app underneath.
        if option { return nil }

        switch keyCode {
        case ClipboardKeyCodes.escape: return .cancel
        case ClipboardKeyCodes.delete: return .backspace
        case ClipboardKeyCodes.upArrow: return .moveUp
        case ClipboardKeyCodes.downArrow: return .moveDown
        case ClipboardKeyCodes.home: return .moveToTop
        case ClipboardKeyCodes.end: return .moveToBottom
        case ClipboardKeyCodes.pageUp: return .pageUp
        case ClipboardKeyCodes.pageDown: return .pageDown
        case ClipboardKeyCodes.leftArrow, ClipboardKeyCodes.rightArrow, ClipboardKeyCodes.tab: return nil
        default: break
        }

        guard let typed = text(), !typed.isEmpty else { return nil }
        // Reject control characters; only real typing feeds the search field.
        guard !typed.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            return nil
        }
        return .character(typed)
    }

    /// Layout-correct text for a key event, so AZERTY/Cyrillic/Dvorak all type what the
    /// user sees on their keycaps.
    ///
    /// Multi-stage IME composition (Chinese, Japanese) is not supported: an event tap
    /// observes key codes, never the composed output of an input method.
    static func text(from event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: length)
    }
}
