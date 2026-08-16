//
//  AnyTransition+NotchTab.swift
//  boringNotch
//

import SwiftUI

extension AnyTransition {
    /// The transition used when switching between tabs in the open notch.
    ///
    /// Declared once and applied to every branch of the tab switch so all tabs animate
    /// identically. Previously only `NotchHomeView` carried a transition — an
    /// asymmetric slide-from-top on insert and a plain fade on removal — while Shelf
    /// and Clipboard fell back to SwiftUI's default crossfade, so Home animated
    /// differently from everything else and differently from itself on the way out.
    ///
    /// Symmetric and deliberately small: the open notch is only ~140pt tall, so a
    /// full-edge move reads as a lurch at this size.
    static var notchTab: AnyTransition {
        .opacity.combined(
            with: .modifier(
                active: NotchTabOffsetModifier(offset: -6),
                identity: NotchTabOffsetModifier(offset: 0)
            )
        )
    }
}

private struct NotchTabOffsetModifier: ViewModifier {
    let offset: CGFloat

    func body(content: Content) -> some View {
        content.offset(y: offset)
    }
}
