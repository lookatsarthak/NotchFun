//
//  MusicLiveActivityMetrics.swift
//  NotchFun
//

import CoreGraphics

/// The sizes of the two slots either side of the closed notch while music is playing.
///
/// Deliberately pure and free of SwiftUI and Defaults, for the same reason
/// `CaffeineIndicatorPolicy` is: the row's widths live in the view body and the row's
/// *total* width lives in `computedChinWidth`, derived separately by hand. When those two
/// disagree the invisible hover chin stops matching the visible row.
///
/// The invariant worth stating out loud, because breaking it is the one thing that ruins
/// the notch: `MusicLiveActivity` is `[artwork][black rectangle][spectrum]`, and that
/// black rectangle only stays over the physical notch because the artwork and the
/// spectrum either side of it are the same width. So `artSize == spectrumHeight`
/// unconditionally, and nothing here may shrink one without the other.
enum MusicLiveActivityMetrics {
    /// Subtracted from the notch height to get a slot. 12 is what the row has always
    /// used; 18 is the compact setting.
    static let standardInset: CGFloat = 12
    static let compactInset: CGFloat = 18

    /// SwiftUI's default `HStack` spacing, which the row used implicitly for years —
    /// **measured at 8pt**, by rendering the row's exact three-child shape through
    /// `NSHostingView` and reading `fittingSize`.
    ///
    /// The `+ 20` that `computedChinWidth` used to add was a hand-fitted guess at these
    /// two gaps, and it was 4pt too generous: the invisible hover chin has always been
    /// 243pt over a 239pt row. Passing 8 explicitly keeps the row pixel-identical to
    /// every previous release and lets the chin finally derive from it.
    static let standardSpacing: CGFloat = 8
    static let compactSpacing: CGFloat = 6

    /// Album art below this is mush rather than art, so compact stops here.
    static let minimumArtSize: CGFloat = 14

    struct Context: Equatable, Sendable {
        /// `vm.effectiveClosedNotchHeight` — 0 when the notch is hidden for fullscreen.
        var closedNotchHeight: CGFloat
        var compact: Bool
        var gestureProgress: CGFloat

        init(closedNotchHeight: CGFloat, compact: Bool, gestureProgress: CGFloat = 0) {
            self.closedNotchHeight = closedNotchHeight
            self.compact = compact
            self.gestureProgress = gestureProgress
        }
    }

    struct Metrics: Equatable, Sendable {
        var artSize: CGFloat
        var spectrumWidth: CGFloat
        var spectrumHeight: CGFloat
        var spacing: CGFloat
        /// What the row adds to `closedNotchSize.width`: both slots plus both gaps.
        /// Derived here so `computedChinWidth` never restates it.
        var addedWidth: CGFloat
    }

    static func metrics(_ context: Context) -> Metrics {
        let standardSlot = max(0, context.closedNotchHeight - standardInset)

        // Compact shrinks the slot, but never below the legibility floor and never
        // *above* the standard slot. Without that second clamp a short custom notch
        // height would make "compact" wider than normal, which is nonsense.
        let slot: CGFloat = context.compact
            ? min(standardSlot, max(minimumArtSize, context.closedNotchHeight - compactInset))
            : standardSlot

        let spacing = context.compact ? compactSpacing : standardSpacing

        return Metrics(
            artSize: slot,
            // The only asymmetry, and it is deliberate: the spectrum stretches under a
            // pan so the row gives way in the direction of the drag. It is transient and
            // returns to `slot` the moment the gesture ends.
            spectrumWidth: max(0, slot + context.gestureProgress / 2),
            spectrumHeight: slot,
            spacing: spacing,
            addedWidth: 2 * slot + 2 * spacing
        )
    }
}
