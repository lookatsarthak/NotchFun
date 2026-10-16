//
//  OnboardingPlan.swift
//  NotchFun
//

import Foundation

/// The choices made during setup that decide which steps, permissions and tasks it has.
///
/// Foundation only, so the sequencing below compiles into the standalone test bundle.
struct OnboardingChoices: Equatable, Sendable {
    var shelf = true
    var clipboardHistory = false
    var calendar = false
    var mirror = false
    /// The volume and brightness popup. Held here rather than written straight to its
    /// setting, because switching that setting on asks for Accessibility immediately -
    /// which would put a system prompt in the middle of the feature grid.
    var mediaKeyHUD = false
    var opensOnHover = true
}

/// What setup starts with for someone setting NotchFun up for the first time.
///
/// These are setup's recommendations, not the app's defaults. Each screen applies its
/// share as it first appears, where every choice can be seen and changed, and only in a
/// first setup. The built-in defaults stay as they were, so an update never switches
/// anything for people who already use NotchFun: clipboard history does not start
/// recording, and the menu bar icon does not disappear.
enum OnboardingRecommendation {
    /// The feature grid.
    struct Features: Equatable, Sendable {
        var nowPlaying = true
        var shelf = true
        var clipboardHistory = true
        var caffeine = false
        var calendar = false
        var mirror = false
        var accessoryBattery = false
        var mediaKeyHUD = true
    }

    /// The preferences screen. Automatic updates and "every display" are left out: their
    /// built-in defaults (on, and off) are already the recommendation.
    struct Preferences: Equatable, Sendable {
        var launchAtLogin = true
        var opensOnHover = true
        /// The face in the closed notch while nothing is playing. A small, steady sign
        /// that NotchFun is there; without it the notch looks like nothing is installed.
        var idleFace = true
        /// Settings stays one click away through the gear in the open notch, and opening
        /// NotchFun again from Applications shows it too.
        var menubarIcon = false
    }

    static let features = Features()
    static let preferences = Preferences()

    /// The feature recommendations as setup's sequencing sees them.
    static var choices: OnboardingChoices {
        OnboardingChoices(
            shelf: features.shelf,
            clipboardHistory: features.clipboardHistory,
            calendar: features.calendar,
            mirror: features.mirror,
            mediaKeyHUD: features.mediaKeyHUD,
            opensOnHover: preferences.opensOnHover
        )
    }

    /// Whether a screen should apply its recommendations now: only in a first setup, and
    /// only once, so going Back and forward again, or quitting and resuming, never undoes
    /// a choice made in between.
    static func shouldApply(completedVersion: Int, alreadyApplied: Bool) -> Bool {
        completedVersion == 0 && !alreadyApplied
    }
}

enum OnboardingStep: String, CaseIterable, Sendable {
    case hello
    case features
    case permissions
    case preferences
    case tryIt
    case done
}

/// In the order they are asked for: data access first, then the one that needs a trip
/// to System Settings.
enum OnboardingPermission: String, CaseIterable, Sendable {
    case calendar
    case reminders
    case camera
    case accessibility
}

enum OnboardingTask: String, CaseIterable, Sendable {
    case openNotch
    case dragToShelf
    case copyText
}

/// Which steps setup has, given the choices so far.
///
/// The rule the whole flow is built on: permissions are asked for only for features
/// that were switched on, and only after they were. The old setup asked for camera,
/// calendar and reminders up front, for features that are off by default.
enum OnboardingPlan {
    /// Raise this to show setup again to people who finished an earlier version.
    static let version = 1

    static func permissions(for choices: OnboardingChoices) -> [OnboardingPermission] {
        var result: [OnboardingPermission] = []
        if choices.calendar { result += [.calendar, .reminders] }
        if choices.mirror { result.append(.camera) }
        // The popup cannot work without it; clipboard history works without it but
        // cannot paste into other apps, which is most of the point.
        if choices.mediaKeyHUD || choices.clipboardHistory { result.append(.accessibility) }
        return result
    }

    static func steps(for choices: OnboardingChoices) -> [OnboardingStep] {
        var steps: [OnboardingStep] = [.hello, .features]
        if !permissions(for: choices).isEmpty { steps.append(.permissions) }
        steps += [.preferences, .tryIt, .done]
        return steps
    }

    /// "Try it" only demonstrates what is switched on: dragging to a shelf that is off,
    /// or copying into a history that is not recording, would teach something false.
    static func tasks(for choices: OnboardingChoices) -> [OnboardingTask] {
        var tasks: [OnboardingTask] = [.openNotch]
        if choices.shelf { tasks.append(.dragToShelf) }
        if choices.clipboardHistory { tasks.append(.copyText) }
        return tasks
    }

    static func next(after step: OnboardingStep, choices: OnboardingChoices) -> OnboardingStep? {
        let steps = steps(for: choices)
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    static func previous(before step: OnboardingStep, choices: OnboardingChoices) -> OnboardingStep? {
        let steps = steps(for: choices)
        guard let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }

    /// What the last screen says when something chosen in setup is waiting on
    /// Accessibility, or nil when nothing is.
    ///
    /// Setup lets people skip the permission, which is right, but a volume popup switched
    /// on and then skipped simply never appeared, and nothing said why. The popup is only
    /// switched on at the end of setup, and only with Accessibility, so someone who allows
    /// it afterwards still has to turn the popup on in Settings.
    static func accessibilityReminder(mediaKeyHUD: Bool, clipboardHistory: Bool, accessibilityGranted: Bool) -> String? {
        guard !accessibilityGranted else { return nil }
        switch (mediaKeyHUD, clipboardHistory) {
        case (true, true):
            return "The volume popup and pasting from clipboard history need Accessibility. If you allow it later, turn the popup on in Settings → HUD."
        case (true, false):
            return "The volume and brightness popup needs Accessibility. If you allow it later, turn the popup on in Settings → HUD."
        case (false, true):
            return "Pasting from clipboard history needs Accessibility."
        case (false, false):
            return nil
        }
    }

    /// Where to pick up after setup was quit part-way. A saved step that no longer
    /// applies - permissions, after the features that needed them were switched off -
    /// resumes at the step that followed it rather than starting over.
    static func resumeStep(saved: String?, choices: OnboardingChoices) -> OnboardingStep {
        guard let saved, let step = OnboardingStep(rawValue: saved) else { return .hello }
        let steps = steps(for: choices)
        if steps.contains(step) { return step }
        let all = OnboardingStep.allCases
        let savedIndex = all.firstIndex(of: step) ?? 0
        return steps.first { (all.firstIndex(of: $0) ?? 0) > savedIndex } ?? .hello
    }

    /// Whether this launch should show setup.
    ///
    /// People who had the app before setup had a version number get one pass: they are
    /// recognised by having finished the old first-launch flow and having no setup in
    /// progress, and are treated as having completed this version.
    static func shouldShow(completedVersion: Int, firstLaunch: Bool, inProgress: Bool) -> Bool {
        if completedVersion >= version { return false }
        if completedVersion == 0, !firstLaunch, !inProgress { return false }
        return true
    }
}
