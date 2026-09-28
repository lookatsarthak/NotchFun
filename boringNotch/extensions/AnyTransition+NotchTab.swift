//
//  AnyTransition+NotchTab.swift
//  NotchFun
//

import SwiftUI

extension AnyTransition {
    /// The transition used when switching between tabs in the open notch.
    ///
    /// Declared once and applied to every branch of the tab switch so all tabs animate
    /// identically; before that, Home animated differently from Shelf and Clipboard.
    /// Resolved through NotchMotion.transition, so under Reduce Motion it becomes a
    /// plain cross-fade rather than a shorter slide.
    ///
    /// Direction-aware: the incoming tab slides in from the side it sits on in the tab
    /// bar, so a switch says which way you moved. Previously every switch was the same
    /// small vertical drift, identical in both directions, and easy to miss entirely.
    ///
    /// Only the incoming view moves. A removed view animates with the transition it
    /// last rendered with, which was attached before the direction of *this* switch was
    /// known, so a directional exit would sometimes go the wrong way. It just fades, and
    /// faster than the new one arrives (NotchMotion.exit), so the two do not smear.
    ///
    /// Both timings live here rather than on the call site: an `.animation` applied to
    /// the whole transition there overrides the ones inside it, which silently undid
    /// the faster exit.
    ///
    /// 16pt, not a full-width push: the open notch is small, and a large move reads as
    /// a lurch at this size.
    static func notchTab(direction: CGFloat) -> AnyTransition {
        NotchMotion.transition(
            .asymmetric(
                insertion: AnyTransition.opacity.combined(
                    with: .modifier(
                        active: NotchTabOffsetModifier(x: 16 * direction),
                        identity: NotchTabOffsetModifier(x: 0)
                    )
                ).animation(NotchMotion.content),
                removal: AnyTransition.opacity.animation(NotchMotion.exit)
            )
        )
    }
}

private struct NotchTabOffsetModifier: ViewModifier {
    let x: CGFloat

    func body(content: Content) -> some View {
        content.offset(x: x)
    }
}
