//
//  NotchAppIntents.swift
//  NotchFun
//

import AppIntents
import Foundation

/// The only file in the project that imports AppIntents.
///
/// Deliberately so. The test bundle is standalone — it compiles sources under test
/// directly and links no packages — and `CaffeineDuration.swift`, `CaffeineMode.swift`
/// and friends are all in it. Conforming any of those model types to `AppEnum` in place
/// would drag AppIntents into that bundle. The option types below are separate on
/// purpose, and map to the real types here.
///
/// What these add over the keyboard shortcuts in `ShortcutConstants.swift` is
/// **parameters**: a hotkey is one key to one fixed action with no arguments and no
/// return value, so "caffeine for 30 minutes" cannot be a hotkey but is trivial here.

// MARK: - Option types

enum NotchToggleState: String, AppEnum {
    case on
    case off
    case toggle

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "State" }

    static var caseDisplayRepresentations: [NotchToggleState: DisplayRepresentation] {
        [.on: "On", .off: "Off", .toggle: "Toggle"]
    }

    var asDesired: NotchActions.DesiredState {
        switch self {
        case .on: return .on
        case .off: return .off
        case .toggle: return .toggle
        }
    }
}

enum NotchTabOption: String, AppEnum {
    case home
    case shelf
    case clipboard

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Notch Tab" }

    static var caseDisplayRepresentations: [NotchTabOption: DisplayRepresentation] {
        [.home: "Home", .shelf: "Shelf", .clipboard: "Clipboard"]
    }

    var asNotchView: NotchViews {
        switch self {
        case .home: return .home
        case .shelf: return .shelf
        case .clipboard: return .clipboard
        }
    }
}

/// Mirrors `CaffeineDuration.presets`.
///
/// `whileAppRunning` is deliberately not offered: it carries an associated bundle ID, so
/// exposing it would mean an `AppEntity` and an `EntityQuery` to pick an application —
/// a lot of surface for a case the menu already handles well.
enum CaffeineDurationOption: String, AppEnum {
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case indefinite

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Duration" }

    static var caseDisplayRepresentations: [CaffeineDurationOption: DisplayRepresentation] {
        [
            .fiveMinutes: "5 minutes",
            .fifteenMinutes: "15 minutes",
            .thirtyMinutes: "30 minutes",
            .oneHour: "1 hour",
            .twoHours: "2 hours",
            .indefinite: "Until turned off",
        ]
    }

    var asDuration: CaffeineDuration {
        switch self {
        case .fiveMinutes: return .minutes(5)
        case .fifteenMinutes: return .minutes(15)
        case .thirtyMinutes: return .minutes(30)
        case .oneHour: return .hours(1)
        case .twoHours: return .hours(2)
        case .indefinite: return .indefinite
        }
    }
}

// MARK: - Intents

struct SetCaffeineIntent: AppIntent {
    static var title: LocalizedStringResource { "Set Caffeine" }
    static var description: IntentDescription {
        IntentDescription("Keep the Mac awake, optionally for a set time.")
    }
    /// False on every intent here. NotchFun is an accessory app that is already running,
    /// and bringing it forward would steal focus from whatever the user is doing.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "State", default: .toggle)
    var state: NotchToggleState

    @Parameter(title: "Duration")
    var duration: CaffeineDurationOption?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let isOn = NotchActions.setCaffeine(state.asDesired, duration: duration?.asDuration)
        return .result(value: isOn)
    }
}

struct OpenNotchIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Notch" }
    static var description: IntentDescription {
        IntentDescription("Open the notch, optionally on a particular tab.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Tab")
    var tab: NotchTabOption?

    /// Off by default so a bare "Open Notch" behaves like the ⇧⌘I shortcut and gets out
    /// of the way. On when the user is about to read something.
    @Parameter(title: "Keep open", default: false)
    var keepOpen: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        NotchActions.openNotch(tab: tab?.asNotchView, autoClose: !keepOpen)
        return .result()
    }
}

struct CloseNotchIntent: AppIntent {
    static var title: LocalizedStringResource { "Close Notch" }
    static var description: IntentDescription { IntentDescription("Close the notch.") }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotchActions.closeNotch()
        return .result()
    }
}

struct PasteAsPlainTextIntent: AppIntent {
    static var title: LocalizedStringResource { "Paste as Plain Text" }
    static var description: IntentDescription {
        IntentDescription("Paste what is on the clipboard, without its formatting.")
    }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        // False rather than a thrown error: "there was nothing to paste" is a normal
        // outcome for an automation, not a failure worth stopping a Shortcut over.
        return .result(value: NotchActions.pasteAsPlainText())
    }
}

struct SetClipboardHistoryIntent: AppIntent {
    static var title: LocalizedStringResource { "Set Clipboard History" }
    static var description: IntentDescription {
        IntentDescription(
            "Turn clipboard history recording on or off — useful before screen sharing."
        )
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "State", default: .toggle)
    var state: NotchToggleState

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        return .result(value: NotchActions.setClipboardHistory(state.asDesired))
    }
}

// MARK: - Spoken and Spotlight phrases

/// Three, deliberately. Each phrase must contain `\(.applicationName)` or metadata
/// extraction fails the build, and every phrase is a localisation entry — a long list
/// costs more to maintain than it buys.
///
/// `updateAppShortcutParameters()` is never called anywhere: none of these have dynamic
/// parameter options, and calling it on a schedule would be a wakeup source.
struct NotchAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetCaffeineIntent(),
            phrases: ["Toggle caffeine in \(.applicationName)"],
            shortTitle: "Toggle Caffeine",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: OpenNotchIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Notch",
            systemImageName: "macbook"
        )
        AppShortcut(
            intent: PasteAsPlainTextIntent(),
            phrases: ["Paste plain text with \(.applicationName)"],
            shortTitle: "Paste as Plain Text",
            systemImageName: "doc.on.clipboard"
        )
    }
}
