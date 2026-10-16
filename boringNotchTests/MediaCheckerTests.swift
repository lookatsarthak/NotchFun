//
//  MediaCheckerTests.swift
//  boringNotchTests
//

import Foundation
import Testing

/// Now Playing is only declared unavailable when the probe keeps saying so. A single miss,
/// as at login while mediaremoted starts, once switched Now Playing off until the next
/// update and showed the choose-a-source prompt on every launch.
@Suite("Now Playing availability")
struct MediaCheckerTests {
    /// A probe that answers from a script, and counts how often it was asked.
    final class Probe: @unchecked Sendable {
        var answers: [Bool]
        var calls = 0
        init(_ answers: [Bool]) { self.answers = answers }
        func run() throws -> Bool {
            calls += 1
            return answers.isEmpty ? true : answers.removeFirst()
        }
    }

    @Test("Available on the first try is believed at once")
    func availableAtOnce() async throws {
        let probe = Probe([false])
        #expect(try await !MediaChecker.confirmedDeprecation(pause: .zero) { try probe.run() })
        #expect(probe.calls == 1)
    }

    @Test("One unavailable answer followed by an available one is a miss, not a verdict")
    func singleMissIgnored() async throws {
        let probe = Probe([true, false])
        #expect(try await !MediaChecker.confirmedDeprecation(pause: .zero) { try probe.run() })
        #expect(probe.calls == 2)
    }

    @Test("Unavailable every time is unavailable")
    func repeatedUnavailable() async throws {
        let probe = Probe([true, true, true])
        #expect(try await MediaChecker.confirmedDeprecation(pause: .zero) { try probe.run() })
        #expect(probe.calls == 3)
    }

    @Test("A probe that fails outright is reported, not read as unavailable")
    func errorsPropagate() async {
        struct Broken: Error {}
        await #expect(throws: Broken.self) {
            try await MediaChecker.confirmedDeprecation(pause: .zero) { throw Broken() }
        }
    }
}
