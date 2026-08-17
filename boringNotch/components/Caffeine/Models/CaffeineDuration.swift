//
//  CaffeineDuration.swift
//  boringNotch
//

import Foundation

/// How long a caffeine session should last.
enum CaffeineDuration: Codable, Hashable, Sendable {
    case indefinite
    case minutes(Int)
    case hours(Int)
    /// Stays on for as long as a given application is running — the Amphetamine-style
    /// trigger. Uses `NSWorkspace` termination notifications, so no polling and no
    /// permissions.
    case whileAppRunning(bundleID: String, name: String)

    /// The presets offered in the menu.
    static let presets: [CaffeineDuration] = [
        .minutes(5), .minutes(15), .minutes(30), .hours(1), .hours(2), .indefinite
    ]

    /// Seconds from now, or `nil` when the session has no fixed end.
    var timeInterval: TimeInterval? {
        switch self {
        case .indefinite, .whileAppRunning: return nil
        case .minutes(let m): return TimeInterval(m * 60)
        case .hours(let h): return TimeInterval(h * 3600)
        }
    }

    var title: String {
        switch self {
        case .indefinite: return "Until I turn it off"
        case .minutes(let m): return "\(m) minutes"
        case .hours(let h): return h == 1 ? "1 hour" : "\(h) hours"
        case .whileAppRunning(_, let name): return "While \(name) is running"
        }
    }

    /// Compact form for the notch, where there is very little room.
    var shortTitle: String {
        switch self {
        case .indefinite: return "∞"
        case .minutes(let m): return "\(m)m"
        case .hours(let h): return "\(h)h"
        case .whileAppRunning(_, let name): return name
        }
    }
}
