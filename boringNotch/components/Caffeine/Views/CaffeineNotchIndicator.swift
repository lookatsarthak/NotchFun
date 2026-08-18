//
//  CaffeineNotchIndicator.swift
//  boringNotch
//

import SwiftUI

/// The cup shown in a slot of the closed notch while caffeine is on.
///
/// Status only: deliberately not a button and not hoverable, so it cannot interfere with
/// the hover-to-open and drag-to-shelf gestures that own the closed notch. Toggling
/// caffeine is the header button's job, or the right-click menu's.
struct CaffeineNotchIndicator: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "cup.and.saucer.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            // White, like the other notch glyphs. See CaffeineButton for why not accent.
            .foregroundStyle(.white)
            .frame(width: max(0, size * 0.62), height: max(0, size * 0.62))
            .frame(width: size, height: size)
            .accessibilityLabel("Caffeine is on")
    }
}
