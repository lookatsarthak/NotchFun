//
//  CaffeineManagerTests.swift
//  boringNotchTests
//

import Foundation
import Testing

/// The invariant under test throughout: the assertion is held if and only if there is a
/// session. A missed release means the user's Mac never sleeps again, which is the one
/// failure this feature cannot afford.
@Suite("CaffeineManager lifecycle")
@MainActor
struct CaffeineManagerTests {
    private func makeManager() -> (CaffeineManager, FakeAssertion, InMemoryCaffeineSessionStore) {
        let assertion = FakeAssertion()
        let store = InMemoryCaffeineSessionStore()
        return (CaffeineManager(assertion: assertion, store: store), assertion, store)
    }

    @Test("Starts with nothing held")
    func startsInactive() {
        let (manager, assertion, _) = makeManager()
        #expect(!manager.isActive)
        #expect(!assertion.isHeld)
    }

    @Test("Activating takes the assertion and persists the session")
    func activate() {
        let (manager, assertion, store) = makeManager()
        manager.activate(mode: .displayAwake, duration: .minutes(15), now: testEpoch)
        #expect(manager.isActive)
        #expect(assertion.isHeld)
        #expect(assertion.lastMode == .displayAwake)
        #expect(store.load() != nil)
    }

    @Test("Activating again replaces the assertion instead of stacking a second one")
    func reactivateDoesNotStack() {
        let (manager, assertion, _) = makeManager()
        manager.activate(mode: .displayAwake, duration: .minutes(15), now: testEpoch)
        let holdsBefore = assertion.holdCount

        manager.activate(mode: .systemAwake, duration: .hours(1), now: testEpoch)
        #expect(assertion.holdCount == holdsBefore + 1)
        #expect(assertion.lastMode == .systemAwake)
    }

    @Test("Deactivating releases, clears storage, and is safe to repeat")
    func deactivate() {
        let (manager, assertion, store) = makeManager()
        manager.activate(mode: .displayAwake, duration: .minutes(15), now: testEpoch)

        manager.deactivate()
        #expect(!manager.isActive)
        #expect(!assertion.isHeld)
        #expect(store.load() == nil)

        manager.deactivate()
        #expect(!assertion.isHeld)
    }

    @Test("The countdown turns caffeine off at the deadline")
    func expiry() {
        let (manager, assertion, store) = makeManager()
        manager.activate(mode: .displayAwake, duration: .minutes(5), now: testEpoch)

        manager.tick(now: testEpoch.addingTimeInterval(299))
        #expect(manager.isActive)
        #expect(assertion.isHeld)

        manager.tick(now: testEpoch.addingTimeInterval(300))
        #expect(!manager.isActive)
        #expect(!assertion.isHeld)
        #expect(store.load() == nil)
    }

    @Test("A deadline that passed while the Mac slept is honoured on wake")
    func wakeAfterDeadline() {
        // This is why the session stores an absolute end time: a Timer does not fire
        // while asleep, so a one-hour session would otherwise survive a two-hour nap.
        let (manager, assertion, _) = makeManager()
        manager.activate(mode: .displayAwake, duration: .hours(1), now: testEpoch)

        manager.handleWake(now: testEpoch.addingTimeInterval(7200))
        #expect(!manager.isActive)
        #expect(!assertion.isHeld)
    }

    @Test("Waking before the deadline re-takes an assertion macOS dropped")
    func wakeReTakesAssertion() {
        let (manager, assertion, _) = makeManager()
        manager.activate(mode: .displayAwake, duration: .hours(2), now: testEpoch)

        assertion.release()   // simulate the system dropping it across sleep
        #expect(!assertion.isHeld)

        manager.handleWake(now: testEpoch.addingTimeInterval(60))
        #expect(manager.isActive)
        #expect(assertion.isHeld)
    }

    @Test("Only the bound app quitting turns caffeine off")
    func boundAppTermination() {
        let (manager, assertion, _) = makeManager()
        manager.activate(
            mode: .displayAwake,
            duration: .whileAppRunning(bundleID: "com.example.app", name: "Example"),
            now: testEpoch
        )

        manager.handleAppTerminated(bundleID: "com.other.app", name: "Other")
        #expect(manager.isActive)
        #expect(assertion.isHeld)

        manager.handleAppTerminated(bundleID: "com.example.app", name: "Example")
        #expect(!manager.isActive)
        #expect(!assertion.isHeld)
    }

    @Test("A failed assertion leaves no half state behind")
    func failedActivation() {
        let (manager, assertion, store) = makeManager()
        assertion.shouldFail = true

        let ok = manager.activate(mode: .displayAwake, duration: .indefinite, now: testEpoch)
        #expect(!ok)
        #expect(!manager.isActive)
        #expect(!assertion.isHeld)
        #expect(store.load() == nil)
    }

    @Test("Toggle turns caffeine on and back off")
    func toggle() {
        let (manager, _, _) = makeManager()
        #expect(manager.toggle(mode: .displayAwake, duration: .indefinite))
        #expect(manager.isActive)
        #expect(!manager.toggle(mode: .displayAwake, duration: .indefinite))
        #expect(!manager.isActive)
    }

    @Test("A trigger the user enabled switches caffeine on")
    func autoTriggerActivates() {
        let (manager, assertion, _) = makeManager()
        manager.configureAutoTriggers(isEnabled: { _ in true }, mode: { .displayAwake })

        manager.handleAutoTrigger(.powerConnected, active: true)
        #expect(manager.isActive)
        #expect(assertion.isHeld)
    }

    @Test("A trigger the user did not enable does nothing")
    func autoTriggerRespectsSetting() {
        let (manager, assertion, _) = makeManager()
        manager.configureAutoTriggers(isEnabled: { _ in false }, mode: { .displayAwake })

        manager.handleAutoTrigger(.powerConnected, active: true)
        #expect(!manager.isActive)
        #expect(!assertion.isHeld)
    }

    @Test("Unplugging ends a session the trigger started")
    func autoTriggerDeactivatesItsOwnSession() {
        let (manager, assertion, _) = makeManager()
        manager.configureAutoTriggers(isEnabled: { _ in true }, mode: { .displayAwake })

        manager.handleAutoTrigger(.powerConnected, active: true)
        manager.handleAutoTrigger(.powerConnected, active: false)
        #expect(!manager.isActive)
        #expect(!assertion.isHeld)
    }

    @Test("Unplugging never cancels a session the user started")
    func autoTriggerLeavesManualSessionsAlone() {
        // Having your Mac decide to stop staying awake because you moved to battery is a
        // worse surprise than it staying on.
        let (manager, assertion, _) = makeManager()
        manager.configureAutoTriggers(isEnabled: { _ in true }, mode: { .displayAwake })

        manager.activate(mode: .displayAwake, duration: .indefinite, now: testEpoch)
        manager.handleAutoTrigger(.powerConnected, active: false)
        #expect(manager.isActive)
        #expect(assertion.isHeld)
    }

    @Test("A trigger firing while already on does not restart the session")
    func autoTriggerDoesNotDisturbAnActiveSession() {
        let (manager, assertion, _) = makeManager()
        manager.configureAutoTriggers(isEnabled: { _ in true }, mode: { .displayAwake })
        manager.activate(mode: .systemAwake, duration: .indefinite, now: testEpoch)
        let holds = assertion.holdCount

        manager.handleAutoTrigger(.externalDisplay, active: true)
        #expect(assertion.holdCount == holds)
        #expect(assertion.lastMode == .systemAwake)
    }

    @Test("Quitting releases the assertion")
    func termination() {
        let (manager, assertion, _) = makeManager()
        manager.activate(mode: .displayAwake, duration: .indefinite, now: testEpoch)

        manager.releaseForTermination()
        #expect(!assertion.isHeld)
    }
}

@Suite("CaffeineManager restore")
@MainActor
struct CaffeineRestoreTests {
    @Test("A session that expired while the app was closed is dropped")
    func expiredSessionDropped() {
        let store = InMemoryCaffeineSessionStore(
            session: CaffeineSession(mode: .displayAwake, duration: .minutes(5), startedAt: testEpoch)
        )
        let manager = CaffeineManager(assertion: FakeAssertion(), store: store)

        manager.restore(now: testEpoch.addingTimeInterval(600))
        #expect(!manager.isActive)
        #expect(store.load() == nil)
    }

    @Test("A session still within its window resumes, in the mode it was saved with")
    func liveSessionResumes() {
        let store = InMemoryCaffeineSessionStore(
            session: CaffeineSession(mode: .systemAwake, duration: .hours(3), startedAt: testEpoch)
        )
        let assertion = FakeAssertion()
        let manager = CaffeineManager(assertion: assertion, store: store)

        manager.restore(now: testEpoch.addingTimeInterval(60))
        #expect(manager.isActive)
        #expect(assertion.isHeld)
        #expect(assertion.lastMode == .systemAwake)
    }

    @Test("A session bound to an app that is no longer running is dropped")
    func boundAppGone() {
        let store = InMemoryCaffeineSessionStore(
            session: CaffeineSession(
                mode: .displayAwake,
                duration: .whileAppRunning(bundleID: "com.nope.notrunning", name: "Nope"),
                startedAt: testEpoch
            )
        )
        let manager = CaffeineManager(assertion: FakeAssertion(), store: store)

        manager.restore(now: testEpoch.addingTimeInterval(60))
        #expect(!manager.isActive)
    }
}
