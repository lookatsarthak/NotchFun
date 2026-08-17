//
//  CaffeineNotification.swift
//  boringNotch
//

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
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Text(isActive ? "Caffeine on" : "Caffeine off")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }

            Rectangle()
                .fill(.black)
                .frame(width: notchWidth + 10)

            HStack(spacing: 4) {
                if let detail, isActive {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                Image(systemName: isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(isActive ? Color.effectiveAccent : .gray)
                    .imageScale(.medium)
            }
            .frame(width: 76, alignment: .trailing)
        }
    }
}
