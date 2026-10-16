//
//  OnboardingPlanTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Onboarding plan")
struct OnboardingPlanTests {
    @Test("No permission step when nothing needing one is switched on")
    func noPermissionsStep() {
        let steps = OnboardingPlan.steps(for: OnboardingChoices())
        #expect(steps == [.hello, .features, .preferences, .tryIt, .done])
    }

    @Test("Permissions are asked only for what was switched on")
    func permissionsFollowFeatures() {
        var choices = OnboardingChoices()
        choices.calendar = true
        #expect(OnboardingPlan.permissions(for: choices) == [.calendar, .reminders])

        choices = OnboardingChoices()
        choices.mirror = true
        #expect(OnboardingPlan.permissions(for: choices) == [.camera])

        choices = OnboardingChoices()
        choices.mediaKeyHUD = true
        choices.clipboardHistory = true
        #expect(OnboardingPlan.permissions(for: choices) == [.accessibility])
        #expect(OnboardingPlan.steps(for: choices).contains(.permissions))
    }

    @Test("Try it only demonstrates features that are on")
    func tasksFollowFeatures() {
        var choices = OnboardingChoices()
        choices.shelf = false
        #expect(OnboardingPlan.tasks(for: choices) == [.openNotch])

        choices.shelf = true
        choices.clipboardHistory = true
        #expect(OnboardingPlan.tasks(for: choices) == [.openNotch, .dragToShelf, .copyText])
    }

    @Test("Next and back skip a permission step that does not apply")
    func navigation() {
        let choices = OnboardingChoices()
        #expect(OnboardingPlan.next(after: .features, choices: choices) == .preferences)
        #expect(OnboardingPlan.previous(before: .preferences, choices: choices) == .features)
        #expect(OnboardingPlan.next(after: .done, choices: choices) == nil)
        #expect(OnboardingPlan.previous(before: .hello, choices: choices) == nil)
    }

    @Test("Resuming at a step that no longer applies moves to the one after it")
    func resume() {
        let none = OnboardingChoices()
        #expect(OnboardingPlan.resumeStep(saved: nil, choices: none) == .hello)
        #expect(OnboardingPlan.resumeStep(saved: "garbage", choices: none) == .hello)
        #expect(OnboardingPlan.resumeStep(saved: "tryIt", choices: none) == .tryIt)
        #expect(OnboardingPlan.resumeStep(saved: "permissions", choices: none) == .preferences)
    }

    @Test("Existing users are not sent through setup; new and part-way users are")
    func shouldShow() {
        // Brand new install.
        #expect(OnboardingPlan.shouldShow(completedVersion: 0, firstLaunch: true, inProgress: false))
        // Quit part-way: firstLaunch is already cleared, but setup is in progress.
        #expect(OnboardingPlan.shouldShow(completedVersion: 0, firstLaunch: false, inProgress: true))
        // Had the app before setup was versioned.
        #expect(!OnboardingPlan.shouldShow(completedVersion: 0, firstLaunch: false, inProgress: false))
        // Finished this version.
        #expect(!OnboardingPlan.shouldShow(completedVersion: OnboardingPlan.version, firstLaunch: false, inProgress: false))
    }

    @Test("The recommended features: Now playing, Shelf, Clipboard history and the volume popup")
    func recommendedFeatures() {
        let features = OnboardingRecommendation.features
        #expect(features.nowPlaying && features.shelf && features.clipboardHistory && features.mediaKeyHUD)
        #expect(!features.caffeine && !features.calendar && !features.mirror && !features.accessoryBattery)
    }

    @Test("The recommended preferences: login, hover and the face on; the menu bar icon off")
    func recommendedPreferences() {
        let preferences = OnboardingRecommendation.preferences
        #expect(preferences.launchAtLogin && preferences.opensOnHover && preferences.idleFace)
        #expect(!preferences.menubarIcon)
    }

    @Test("Following the recommendations asks for Accessibility only, and tries all three tasks")
    func recommendedFlow() {
        let choices = OnboardingRecommendation.choices
        #expect(OnboardingPlan.permissions(for: choices) == [.accessibility])
        #expect(OnboardingPlan.steps(for: choices) == [.hello, .features, .permissions, .preferences, .tryIt, .done])
        #expect(OnboardingPlan.tasks(for: choices) == [.openNotch, .dragToShelf, .copyText])
    }

    @Test("Recommendations apply once, in a first setup only")
    func recommendationsApplyOnce() {
        #expect(OnboardingRecommendation.shouldApply(completedVersion: 0, alreadyApplied: false))
        // Back and forward again, or quit and resumed: never re-applied over a change.
        #expect(!OnboardingRecommendation.shouldApply(completedVersion: 0, alreadyApplied: true))
        // Existing users, including anyone running setup again from Settings.
        #expect(!OnboardingRecommendation.shouldApply(completedVersion: OnboardingPlan.version, alreadyApplied: false))
    }

    @Test("The last screen names what is waiting on Accessibility, and nothing once it is allowed")
    func accessibilityReminder() {
        let both = OnboardingPlan.accessibilityReminder(mediaKeyHUD: true, clipboardHistory: true, accessibilityGranted: false)
        #expect(both?.contains("volume popup") == true && both?.contains("clipboard") == true && both?.contains("Settings → HUD") == true)
        let popup = OnboardingPlan.accessibilityReminder(mediaKeyHUD: true, clipboardHistory: false, accessibilityGranted: false)
        #expect(popup?.contains("Settings → HUD") == true && popup?.contains("clipboard") == false)
        let paste = OnboardingPlan.accessibilityReminder(mediaKeyHUD: false, clipboardHistory: true, accessibilityGranted: false)
        #expect(paste?.contains("clipboard") == true && paste?.contains("HUD") == false)
        #expect(OnboardingPlan.accessibilityReminder(mediaKeyHUD: false, clipboardHistory: false, accessibilityGranted: false) == nil)
        #expect(OnboardingPlan.accessibilityReminder(mediaKeyHUD: true, clipboardHistory: true, accessibilityGranted: true) == nil)
    }
}
