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
struct NotchBannerRow<Leading: View, Trailing: View>: View {
    /// `vm.closedNotchSize.width`. The `+ 10` bleed matches what both banners already used.
    let notchWidth: CGFloat
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            HStack { leading }

            Rectangle()
                .fill(.black)
                .frame(width: notchWidth + 10)

            HStack(spacing: 4) { trailing }
                // Fixed, not intrinsic. The trailing side must not resize with its
                // content, or a longer label would slide the black spacer off the notch.
                .frame(width: 76, alignment: .trailing)
        }
    }
}
