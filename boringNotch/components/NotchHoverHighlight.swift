//
//  NotchHoverHighlight.swift
//  NotchFun
//

import SwiftUI

/// The fill for a selected or hovered control on the notch - the tab pill, and header
/// buttons under the pointer - so every control on the notch highlights the same way.
///
/// Opaque, deliberately not Liquid Glass. The notch is a transparent window that draws
/// black, so glass here samples the *desktop* behind the window rather than the notch:
/// tried on the tab pill, it came out light grey over a dark wallpaper, made the white
/// tab icon on it unreadable, and its container visibly tinted the black notch around
/// it. What it looks like would depend on each user's wallpaper, which cannot be tested
/// for. A flat fill looks the same on every Mac. HoverButton reached the same
/// conclusion for the music controls.
enum NotchHighlight {
    static let fill = Color.white.opacity(0.16)
    /// A hairline edge, so the pill still reads as an object when the fill is faint.
    static let edge = Color.white.opacity(0.14)
}

/// Header icon buttons: clear at rest, a highlight circle under the pointer. These used
/// to be black circles on the black notch with no hover state at all, so they looked
/// like labels rather than buttons.
struct NotchHoverHighlight: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .frame(width: 30, height: 30)
            .background {
                Circle()
                    .fill(NotchHighlight.fill)
                    .overlay(Circle().strokeBorder(NotchHighlight.edge, lineWidth: 0.5))
                    .opacity(hovering ? 1 : 0)
            }
            .contentShape(Circle())
            .onHover { inside in
                withAnimation(NotchMotion.control) { hovering = inside }
            }
    }
}

extension View {
    func notchHoverHighlight() -> some View {
        modifier(NotchHoverHighlight())
    }
}
