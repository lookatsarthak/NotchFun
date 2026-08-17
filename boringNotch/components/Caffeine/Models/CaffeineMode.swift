//
//  CaffeineMode.swift
//  boringNotch
//

import Foundation

/// What exactly is being kept awake.
///
/// The distinction matters more than it looks: most "keep awake didn't work" reports
/// are someone expecting their screen to stay on and getting only system wake, so both
/// are offered and the display one is the default.
///
/// Neither mode survives closing the lid, and neither overrides a critical-battery
/// sleep — see the limitations section in `PowerAssertion.swift` for why, and what
/// adding lid support would actually cost.
enum CaffeineMode: String, Codable, CaseIterable, Sendable {
    /// Display stays on, and the system stays awake with it.
    case displayAwake
    /// System stays awake but the display is allowed to sleep. Useful for long
    /// downloads or builds where you don't want the screen burning power.
    case systemAwake

    var title: String {
        switch self {
        case .displayAwake: return "Keep display on"
        case .systemAwake: return "Allow display to sleep"
        }
    }

    var detail: String {
        switch self {
        case .displayAwake: return "Nothing sleeps while caffeine is on."
        case .systemAwake: return "The Mac stays awake but the screen can turn off."
        }
    }
}
