//
//  ClipboardRetention.swift
//  NotchFun
//

import Foundation

/// How long an unused clip stays in history.
///
/// History used to be limited only by count, so a clip - a phone number, an API key -
/// could stay for months on a Mac that copies little. This forgets clips nobody has used
/// in a while. "Used" means copied or pasted again from history, so something you reach
/// for regularly never expires however old it is. Pinned clips are never forgotten.
enum ClipboardRetention: String, CaseIterable, Codable, Sendable {
    case never, day, week, month, threeMonths

    /// How long a clip may go unused, or `nil` to keep it until the count limit drops it.
    var interval: TimeInterval? {
        switch self {
        case .never: return nil
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .threeMonths: return 90 * 86_400
        }
    }

    var title: String {
        switch self {
        case .never: return "Never"
        case .day: return "1 day"
        case .week: return "1 week"
        case .month: return "1 month"
        case .threeMonths: return "3 months"
        }
    }

    /// The setting a Mac starts with, chosen once, when the setting first appears.
    ///
    /// A week for someone new. Never for anyone who already had NotchFun: applying a
    /// limit to them would delete their older clips on update, and nobody should lose
    /// data to an update. They can choose a limit in Settings.
    static func initial(isExistingUser: Bool) -> ClipboardRetention {
        isExistingUser ? .never : .week
    }
}
