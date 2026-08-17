//
//  CaffeineSessionTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Caffeine session maths")
struct CaffeineSessionTests {
    @Test("An indefinite session never ends on its own")
    func indefiniteNeverExpires() {
        let session = CaffeineSession(mode: .displayAwake, duration: .indefinite, startedAt: testEpoch)
        #expect(session.expiresAt == nil)
        #expect(!session.isExpired(at: testEpoch.addingTimeInterval(86_400 * 30)))
        #expect(session.remaining(at: testEpoch) == nil)
        #expect(session.remainingLabel(at: testEpoch) == nil)
    }

    @Test("A timed session expires exactly at its deadline")
    func timedExpiry() {
        let session = CaffeineSession(mode: .displayAwake, duration: .minutes(15), startedAt: testEpoch)
        #expect(session.expiresAt == testEpoch.addingTimeInterval(900))
        #expect(!session.isExpired(at: testEpoch.addingTimeInterval(899)))
        #expect(session.isExpired(at: testEpoch.addingTimeInterval(900)))
        #expect(session.isExpired(at: testEpoch.addingTimeInterval(10_000)))
        #expect(session.remaining(at: testEpoch.addingTimeInterval(300)) == 600)
        #expect(session.remaining(at: testEpoch.addingTimeInterval(99_999)) == 0)
    }

    @Test("The countdown label never reads short")
    func countdownLabel() {
        let fifteen = CaffeineSession(mode: .displayAwake, duration: .minutes(15), startedAt: testEpoch)
        #expect(fifteen.remainingLabel(at: testEpoch.addingTimeInterval(300)) == "10m")
        #expect(fifteen.remainingLabel(at: testEpoch.addingTimeInterval(880)) == "20s")

        // Regression: minutes used to be floored, so a session started a moment ago
        // reported one minute less than the user just asked for.
        let five = CaffeineSession(mode: .displayAwake, duration: .minutes(5), startedAt: testEpoch)
        #expect(five.remainingLabel(at: testEpoch) == "5m")
        #expect(five.remainingLabel(at: testEpoch.addingTimeInterval(3)) == "5m")

        let twoHours = CaffeineSession(mode: .systemAwake, duration: .hours(2), startedAt: testEpoch)
        #expect(twoHours.remainingLabel(at: testEpoch.addingTimeInterval(3300)) == "1:05")
        #expect(twoHours.remainingLabel(at: testEpoch) == "2:00")
    }

    @Test("App-bound sessions carry their app and have no deadline")
    func appBound() {
        let bound = CaffeineSession(
            mode: .displayAwake,
            duration: .whileAppRunning(bundleID: "com.example.app", name: "Example"),
            startedAt: testEpoch
        )
        #expect(bound.expiresAt == nil)
        #expect(bound.boundAppBundleID == "com.example.app")

        let timed = CaffeineSession(mode: .displayAwake, duration: .minutes(15), startedAt: testEpoch)
        #expect(timed.boundAppBundleID == nil)
    }

    @Test("Sessions survive a round-trip through the store's encoding")
    func persistenceRoundTrip() throws {
        let encoder = JSONEncoder.notchFunISO8601
        let decoder = JSONDecoder.notchFunISO8601

        let timed = CaffeineSession(mode: .displayAwake, duration: .minutes(15), startedAt: testEpoch)
        #expect(try decoder.decode(CaffeineSession.self, from: encoder.encode(timed)) == timed)

        let bound = CaffeineSession(
            mode: .displayAwake,
            duration: .whileAppRunning(bundleID: "com.example.app", name: "Example"),
            startedAt: testEpoch
        )
        #expect(try decoder.decode(CaffeineSession.self, from: encoder.encode(bound)) == bound)
    }
}

@Suite("Caffeine durations")
struct CaffeineDurationTests {
    @Test("Fixed durations convert to seconds")
    func intervals() {
        #expect(CaffeineDuration.minutes(5).timeInterval == 300)
        #expect(CaffeineDuration.hours(1).timeInterval == 3600)
        #expect(CaffeineDuration.indefinite.timeInterval == nil)
        #expect(CaffeineDuration.whileAppRunning(bundleID: "x", name: "X").timeInterval == nil)
    }

    @Test("The menu offers an indefinite option")
    func presets() {
        #expect(CaffeineDuration.presets.contains(.indefinite))
    }

    @Test("Status phrases read as sentences and keep proper nouns intact")
    func phrasing() {
        // Regression: these lines used to be produced by lowercasing `title`, which
        // turned "Until I turn it off" into "until i turn it off" and an app called
        // "TextEdit" into "textedit".
        #expect(CaffeineDuration.indefinite.phrase == "until you turn it off")
        #expect(CaffeineDuration.minutes(5).phrase == "for 5 minutes")
        #expect(CaffeineDuration.hours(1).phrase == "for 1 hour")
        #expect(CaffeineDuration.hours(2).phrase == "for 2 hours")
        #expect(CaffeineDuration.whileAppRunning(bundleID: "com.apple.TextEdit", name: "TextEdit").phrase
                == "while TextEdit is running")
    }
}
