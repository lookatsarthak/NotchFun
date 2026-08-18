//
//  CaffeineIndicatorPolicy.swift
//  boringNotch
//

import Foundation

/// Decides whether the closed notch shows the persistent caffeine cup.
///
/// Deliberately pure and free of Defaults, SwiftUI and the view model. The notch decides
/// its *width* in `computedChinWidth` and its *content* in the view body, from two
/// separate copies of these conditions; if those two ever disagree the notch stays wide
/// with an empty slot. Both now ask this instead, and the rules get unit tests rather
/// than only being checkable by eye.
enum CaffeineIndicatorPolicy {
    struct Context: Equatable, Sendable {
        /// A caffeine session is running.
        var isActive: Bool
        /// The user's "show a cup in the notch" preference.
        var settingEnabled: Bool
        var notchIsClosed: Bool
        /// An app is fullscreen and the notch is hidden for it.
        var hiddenForFullscreen: Bool
        /// A battery, caffeine or download banner currently owns the closed notch.
        var bannerIsShowing: Bool
        /// A volume/brightness/backlight/mic HUD currently owns the closed notch.
        var inlineHUDIsShowing: Bool
    }

    /// The cup is status, never a claim on the notch: anything the user just triggered
    /// takes the row, and the cup comes back when that finishes.
    static func showsIndicator(_ context: Context) -> Bool {
        guard context.isActive, context.settingEnabled else { return false }
        guard context.notchIsClosed, !context.hiddenForFullscreen else { return false }
        return !context.bannerIsShowing && !context.inlineHUDIsShowing
    }
}
