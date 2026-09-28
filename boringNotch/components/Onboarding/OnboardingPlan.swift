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
