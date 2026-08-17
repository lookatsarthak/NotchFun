//
//  PowerAssertion.swift
//  boringNotch
//

import Foundation
import IOKit.pwr_mgt
import os

/// Something that can hold the system awake.
///
/// Abstracted so `CaffeineManager`'s lifecycle can be tested without touching real
/// system power state — a test that actually prevented sleep would be both slow and
/// rude.
protocol PowerAssertionHolding: AnyObject {
    var isHeld: Bool { get }
    /// Takes the assertion. Returns whether it succeeded. Calling this while already
    /// held must replace the existing assertion, never stack a second one.
    @discardableResult
    func hold(mode: CaffeineMode, reason: String) -> Bool
    func release()
}

/// The real implementation, using `IOPMAssertionCreateWithName`.
///
/// This is deliberately *not* the `caffeinate` command-line tool that most keep-awake
/// apps shell out to. NotchFun is sandboxed, so spawning binaries is unreliable — and
/// more importantly a leaked child process would keep the Mac awake after the user
/// turned caffeine off, which is the one failure this feature cannot afford.
/// `IOPMAssertionCreateWithName` is one of the few IOKit calls that works inside the
/// App Sandbox with no entitlement, and the assertion dies with the process.
final class IOPMPowerAssertion: PowerAssertionHolding {
    private static let logger = Logger(subsystem: "io.github.lookatsarthak.notchfun", category: "PowerAssertion")

    private var assertionID: IOPMAssertionID?

    var isHeld: Bool { assertionID != nil }

    @discardableResult
    func hold(mode: CaffeineMode, reason: String) -> Bool {
        // Replace rather than stack. Two assertions would need two releases, and a
        // missed release means the Mac never sleeps again.
        release()

        let type: CFString = switch mode {
        case .displayAwake: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        case .systemAwake: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        }

        var id: IOPMAssertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )

        guard result == kIOReturnSuccess else {
            Self.logger.error("Failed to create power assertion: \(result, privacy: .public)")
            return false
        }

        assertionID = id
        Self.logger.notice("Power assertion held (\(mode.rawValue, privacy: .public))")
        return true
    }

    func release() {
        guard let assertionID else { return }
        let result = IOPMAssertionRelease(assertionID)
        self.assertionID = nil
        if result == kIOReturnSuccess {
            Self.logger.notice("Power assertion released")
        } else {
            Self.logger.error("Failed to release power assertion: \(result, privacy: .public)")
        }
    }

    deinit {
        // Last line of defence. An assertion outliving the process would be invisible
        // to the user and drain their battery.
        release()
    }
}
