//
//  AccessoryBatteryPolicy.swift
//  NotchFun
//

import Foundation

/// Decides whether the closed notch shows the accessory-battery banner.
///
/// Pure and free of Defaults and SwiftUI, for the reason `CaffeineIndicatorPolicy` is:
/// the notch decides its *width* in `computedChinWidth` and its *content* in the view
/// body, from two separate copies of these conditions, and when those disagree the notch
/// sits wide around an empty row.
///
/// The banner is transient by design. There is no permanent slot for accessory battery
/// and there cannot be one: the closed notch has exactly two slots either side of the
/// hardware cut-out, the face and the caffeine cup already contend for them, and slots
/// are added in pairs to keep the black rectangle centred. A third pair would take the
/// resting notch from 183pt to 363pt on a 14-inch MacBook — near enough double the
/// hardware — and the notch would stop reading as itself expanding.
enum AccessoryBatteryPolicy {
    struct Context: Equatable, Sendable {
        /// An accessory with a parsed level is currently connected.
        var hasReading: Bool
        /// The user's "show accessory battery" preference.
        var settingEnabled: Bool
        /// Something asked for the banner — a connect, or the notch being opened.
        var bannerRequested: Bool
        var notchIsClosed: Bool
        /// An app is fullscreen and the notch is hidden for it.
        var hiddenForFullscreen: Bool
        /// The Mac's own power banner currently owns the closed notch.
        var powerBannerIsShowing: Bool
        /// A volume/brightness/backlight/mic HUD currently owns the closed notch.
        var inlineHUDIsShowing: Bool
    }

    /// Ranked below the inline HUD on purpose. You connect earbuds and reach for the
    /// volume keys within a second or two; if this outranked the HUD it would eat the
    /// feedback for that exact gesture. It stays above the caffeine banner, which is
    /// ambient status rather than a response to something just done.
    static func showsBanner(_ context: Context) -> Bool {
        guard context.hasReading, context.settingEnabled, context.bannerRequested else {
            return false
        }
        guard context.notchIsClosed, !context.hiddenForFullscreen else { return false }
        return !context.powerBannerIsShowing && !context.inlineHUDIsShowing
    }
}
