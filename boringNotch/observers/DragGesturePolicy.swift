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

    static func decide(pasteboardChanged: Bool, from start: CGPoint, to current: CGPoint) -> Decision {
        if pasteboardChanged { return .content }
        let distance = hypot(current.x - start.x, current.y - start.y)
        return distance > decisionDistance ? .abandon : .keepWatching
    }
}
