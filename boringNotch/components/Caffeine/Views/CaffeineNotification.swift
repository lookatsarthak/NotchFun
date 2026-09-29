//
//  CaffeineNotification.swift
//  NotchFun
//

import Defaults
import SwiftUI

/// The transient indicator that appears beside the closed notch when caffeine turns on
/// or off.
///
/// Deliberately mirrors the battery notification's layout: a label to the left of the
/// physical notch, a black spacer exactly the width of the notch itself, and a glyph to
/// the right — which is what produces the "expands on both sides" effect.
///
/// Driven by `coordinator.expandingView`, **not** `toggleSneakPeek`. Sneak peek returns
/// early for every type except `.music` unless `Defaults[.hudReplacement]` is enabled,
/// so an indicator built on it would silently never appear for most users.
struct CaffeineNotification: View {
    let isActive: Bool
    let detail: String?
    /// The running session, for its time left. The banner shows for a few seconds, so a
    /// once-a-second tick only runs while it is on screen.
    var session: CaffeineSession? = nil
    @Default(.caffeineShowsTimeLeft) private var showsTimeLeft
    let notchWidth: CGFloat
    /// Shared with `CaffeineNotchIndicator`. When the banner goes away the cup does not
    /// fade out and a second one fade in — the one cup travels to where it lives next.
    /// Only matched while the session is on: an "off" banner has nothing to hand over to.
    var namespace: Namespace.ID?

    var body: some View {
        NotchBannerRow(notchWidth: notchWidth) {
            Text(isActive ? "Caffeine on" : "Caffeine off")
                .font(.subheadline)
                .foregroundStyle(.white)
        } trailing: {
            if isActive, showsTimeLeft, let session, session.expiresAt != nil {
                CaffeineCountdown(session: session)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            } else if let detail, isActive {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            cup
        }
    }

    @ViewBuilder
    private var cup: some View {
        let image = Image(systemName: isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
            .foregroundStyle(isActive ? .white : .gray)
            .imageScale(.medium)
        if let namespace, isActive {
            // isSource: false — the standalone indicator owns the geometry. Both views
            // are in the tree at once during the handover, which is how the morph works,
            // and two sources in one group makes SwiftUI pick between them arbitrarily.
            image.matchedGeometryEffect(id: CaffeineNotchIndicator.morphID, in: namespace, isSource: false)
        } else {
            image
        }
    }
}

/// A timed session's time left, ticking once a second while it is on screen.
struct CaffeineCountdown: View {
    let session: CaffeineSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(session.countdownClock(at: context.date) ?? "")
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(NotchMotion.control, value: session.countdownClock(at: context.date))
        }
    }
}
