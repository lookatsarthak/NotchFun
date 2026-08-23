//
//  NotchRadius.swift
//  boringNotch
//

import CoreGraphics

/// Corner radii, and the arithmetic for nesting them.
///
/// Deliberately free of SwiftUI so the maths can be unit-tested without dragging the view
/// layer into the test bundle.
enum NotchRadius {

    /// A tile inside a panel: shelf items, clipboard thumbnails.
    static let item: CGFloat = 12
    /// A panel inside the notch: the shelf drop zone, the clipboard list.
    static let panel: CGFloat = 16
    /// Small controls: chips, badges, the clear-confirm capsule before it grows.
    static let control: CGFloat = 8

    /// The radius an inner shape needs so its corner shares a centre with its container.
    ///
    /// Nested rounded rectangles look wrong when both use the same radius — the inner
    /// corner is visibly tighter than the gap around it. Sharing a centre means the inner
    /// radius is the outer one minus the padding between them.
    ///
    /// Clamped at 1 rather than 0: a padding large enough to drive this negative means the
    /// inner shape is nearly square, and a square corner inside a round one reads as a
    /// rendering bug rather than a decision.
    static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(1, outer - inset)
    }
}
