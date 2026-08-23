//
//  NotchMotion.swift
//  boringNotch
//

import AppKit
import SwiftUI

/// Every animation in the app, named for the role it plays.
///
/// Before this there were 28 distinct curves across 48 call sites, written by hand at
/// different times with whatever felt right that day. The problem was never that any one
/// of them was wrong — it was that no two surfaces agreed on how fast anything should
/// move, so the app read as several apps sharing a window.
///
/// The values use Apple's perceptual spring model rather than the older
/// `response`/`dampingFraction` spelling: `duration` is how long the motion *feels* and
/// `bounce` runs -1 to 1, where 0 settles flat. Springs rather than easing curves because
/// everything in a notch gets interrupted — the pointer leaves mid-open, the track changes
/// mid-transition — and a spring carries its current velocity into the new target where an
/// easing curve jumps.
///
/// The two shell values are the app's original numbers, renamed rather than retuned:
/// `spring(response: 0.42, dampingFraction: 0.8)` is the same spring as
/// `spring(duration: 0.42, bounce: 0.20)`, since response is the natural period and bounce
/// is one minus the damping ratio. The notch itself does not change.
enum NotchMotion {

    /// The shell expanding. The only token with overshoot: this is the one place the app
    /// should feel like a physical object rather than a resizing rectangle.
    static var shellOpen: Animation { resolve(.spring(duration: 0.42, bounce: 0.20)) }

    /// The shell collapsing. No bounce — a wobble on the way out reads as a glitch, and
    /// the asymmetry with `shellOpen` is deliberate rather than an oversight.
    static var shellClose: Animation { resolve(.spring(duration: 0.45, bounce: 0)) }

    /// Anything living inside the notch: tab swaps, list rows, HUD bars.
    static var content: Animation { resolve(.spring(duration: 0.28, bounce: 0)) }

    /// Controls under the pointer: buttons, toggles, the clear-confirm capsule.
    static var control: Animation { resolve(.spring(duration: 0.20, bounce: 0)) }

    /// Full-panel swaps outside the notch: onboarding steps, settings panes.
    static var page: Animation { resolve(.spring(duration: 0.40, bounce: 0)) }

    /// Following a pointer through a drag.
    ///
    /// Deliberately not one of the tokens above. Those describe motion the app starts and
    /// finishes on its own; this one is being driven by a finger and has to stay glued to
    /// it, which is a different job with different tuning. It lives here so there is still
    /// only one file to look in.
    static var drag: Animation { resolve(.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)) }

    /// How far behind the shell the content follows when the notch opens.
    ///
    /// This is what makes the notch read as one object rather than a box with things in
    /// it: the container starts moving first and the content arrives a beat later. On
    /// close there is no delay — the content leaves first and the shell follows it down.
    static var contentLead: TimeInterval {
        // Zero under Reduce Motion, or the nesting inverts. `resolve` collapses every
        // token to 0.15s, so a fixed 60ms lead would put the content finishing at 0.21s
        // against a 0.15s shell - the content still on screen after the notch has
        // stopped, which is the exact thing the lead exists to prevent, handed to the
        // people most likely to be bothered by it.
        guard !isReduced else { return 0 }
        #if DEBUG
        // Scaled with the tokens. `.delay` is chained after `.speed`, so an unscaled
        // lead shrinks from 18% of the motion to 4% in the one mode built to inspect it.
        if slowMotion { return 0.06 / 0.2 }
        #endif
        return 0.06
    }

    // MARK: - Accessibility

    /// Whether the user has asked the system to reduce motion.
    ///
    /// Read at use time rather than cached: it can change while the app is running, and
    /// an accessibility setting that needs a relaunch to take effect is not honoured.
    static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Swaps a transition that moves for one that does not.
    ///
    /// Apple's guidance is to *replace* motion under Reduce Motion, not to run the same
    /// motion faster, so this returns a cross-fade rather than a shortened slide.
    static func transition(_ transition: AnyTransition) -> AnyTransition {
        isReduced ? .opacity : transition
    }

    // MARK: - Reviewing motion

    #if DEBUG
    /// Multiplies every token's duration by five so animations can actually be watched.
    ///
    /// A 280 ms spring cannot be reviewed by eye or captured in a screenshot, which is
    /// how inconsistencies survived this long. Toggled from the debug menu.
    /// Read once at launch from `defaults write <bundle-id> NotchFunSlowMotion -bool true`
    /// rather than bound to a keystroke, because the point is to inspect animations from
    /// outside the app - a screenshot harness cannot press a shortcut, and a five-times
    /// slower animation is exactly what makes one reviewable in a still.
    nonisolated(unsafe) static var slowMotion =
        UserDefaults.standard.bool(forKey: "NotchFunSlowMotion")
    #endif

    private static func resolve(_ animation: Animation) -> Animation {
        // Reduce Motion wins over everything, including slow motion.
        guard !isReduced else { return .easeOut(duration: 0.15) }
        #if DEBUG
        if slowMotion { return animation.speed(0.2) }
        #endif
        return animation
    }
}
