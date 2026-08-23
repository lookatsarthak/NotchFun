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
    /// Shared with `CaffeineNotification` so the cup in the banner and the cup that stays
    /// behind are the same object to SwiftUI, and one flies into the other instead of the
    /// pair cross-fading.
    static let morphID = "caffeineCup"

    let size: CGFloat
    /// Optional so previews and any non-morphing use site do not have to invent one.
    var namespace: Namespace.ID?

    var body: some View {
        if let namespace {
            cup.matchedGeometryEffect(id: Self.morphID, in: namespace)
        } else {
            cup
        }
    }

    private var cup: some View {
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
