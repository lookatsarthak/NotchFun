//
//  NotchBannerRow.swift
//  NotchFun
//

import SwiftUI

/// The shape every transient banner beside the closed notch takes: something to the left
/// of the physical notch, a black spacer exactly the width of the notch itself, and a
/// glyph to the right.
///
/// That black spacer is the whole trick — it sits over the hardware cut-out, so the two
/// halves read as the notch itself growing sideways rather than as a panel appearing
/// next to it. The power banner and the caffeine banner had each built this row
/// independently with the same magic numbers; getting one of them wrong would have put
/// the cut-out over the wrong pixels, so it lives in one place now.
///
/// **Both sides are always the same width.** The row is centred as a whole, so the spacer
/// only lands on the cut-out when what's either side of it is equally wide. The left side
/// used to take whatever its text needed against a fixed 76pt right side, and a long
/// label ("Design review", "Pods  L 80 · R 79 · Case 100") pushed the spacer right and
/// slid the end of the text under the camera housing. Now the left side is measured, both
/// sides take the wider of it and the right side's 76pt, and the left text hugs the notch
/// from the left while the right glyph keeps its old place.
struct NotchBannerRow<Leading: View, Trailing: View>: View {
    /// The banner's hover area, wide enough for any banner. ContentView uses it too.
    static var chinWidth: CGFloat { 640 }
    /// The right side's glyph box, as it always was.
    static var trailingWidth: CGFloat { 76 }

    /// `vm.closedNotchSize.width`. The `+ 10` bleed matches what both banners already used.
    let notchWidth: CGFloat
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @State private var leadingIdealWidth: CGFloat = 0

    private var spacerWidth: CGFloat { notchWidth + 10 }

    /// Each side's width: the left text's natural width, at least the glyph box, at most
    /// half of what the chin leaves either side of the notch. Longer text truncates.
    private var sideWidth: CGFloat {
        let most = max(Self.trailingWidth, (Self.chinWidth - spacerWidth) / 2)
        return min(max(Self.trailingWidth, leadingIdealWidth.rounded(.up)), most)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack { leading }
                .frame(width: sideWidth, alignment: .trailing)

            Rectangle()
                .fill(.black)
                .frame(width: spacerWidth)

            HStack(spacing: 4) { trailing }
                .frame(width: Self.trailingWidth, alignment: .trailing)
                .frame(width: sideWidth, alignment: .leading)
        }
        // Measured from an unconstrained copy, so the measurement never depends on the
        // width it decides.
        .background(alignment: .leading) {
            HStack { leading }
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { leadingIdealWidth = $0 }
        }
    }
}
