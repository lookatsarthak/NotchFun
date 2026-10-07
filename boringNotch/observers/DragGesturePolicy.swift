//
//  DragGesturePolicy.swift
//  NotchFun
//

import CoreGraphics

/// Decides, pointer sample by pointer sample, whether a mouse-down-and-drag is carrying
/// content toward the notch or is something else — moving a window, selecting text — that
/// the drag detector should stop watching.
///
/// It exists because the first version decided on the very first dragged event, and a
/// source app only puts its payload on the drag pasteboard once the pointer passes its
/// drag threshold, a few points in. A quick drag jumps past that in one sample; a slow
/// one on a trackpad does not, so the detector gave up on it and the notch never opened.
///
/// Distance alone is not enough either: some sources do work before they publish the
/// payload. A screenshot's floating thumbnail writes the image to a temporary file first
/// (about a quarter of a second for a small capture, measured), so an ordinary flick
/// toward the notch is well past the distance by the time anything is on the pasteboard.
/// A gesture is only given up once it has gone past the distance *and* had a moment, from
/// its first movement, for the source to catch up.
enum DragGesturePolicy {
    enum Decision: Equatable {
        /// The pasteboard changed: this is a content drag. Stop asking.
        case content
        /// Too early to tell; check again on the next sample.
        case keepWatching
        /// Moved well past any drag threshold with nothing on the pasteboard.
        case abandon
    }

    /// Beyond every drag threshold macOS apps use (AppKit's is about 3pt, Finder's a
    /// little more), and still small next to the distance to the notch.
    static let decisionDistance: CGFloat = 24

    /// Seconds from the first movement. Room for a source that writes a file before it
    /// publishes the drag (a full-size screenshot takes longer than the 0.25 s measured
    /// for a small one), and still short: a window move or a text selection stops being
    /// watched within about a second.
    static let decisionTime: Double = 1.0

    /// - Parameter elapsed: seconds since the gesture's first movement (not the mouse-down:
    ///   people often press and hold before they move).
    static func decide(pasteboardChanged: Bool, from start: CGPoint, to current: CGPoint, elapsed: Double) -> Decision {
        if pasteboardChanged { return .content }
        let distance = hypot(current.x - start.x, current.y - start.y)
        return distance > decisionDistance && elapsed > decisionTime ? .abandon : .keepWatching
    }
}
