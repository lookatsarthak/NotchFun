//
//  NotchPlacement.swift
//  NotchFun
//

import CoreGraphics

/// One display as it stood at a moment in time.
///
/// Plain values, not `NSScreen`: a stored `NSScreen` is a live object, so comparing it with
/// the current one later can show no difference even though the display changed. Mirroring
/// does exactly that, keeping the same display but giving it a new size.
struct ScreenSnapshot: Hashable, Sendable {
    let uuid: String?
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(uuid: String?, frame: CGRect) {
        self.uuid = uuid
        x = frame.origin.x
        y = frame.origin.y
        width = frame.width
        height = frame.height
    }
}

/// Where the notch window belongs, and when it needs putting back.
///
/// CoreGraphics only, so it compiles into the standalone test bundle.
enum NotchPlacement {
    /// Seconds after a display change at which the window is checked again. Mirroring
    /// reconfigures in stages, and macOS can shift windows after the last notification, so
    /// one placement isn't enough. Only ever scheduled by a display change: idle cost is nil.
    static let settleDelays: [Double] = [0.3, 1, 2.5]

    /// Centred on the screen and hanging from its top edge. AppKit's origin is bottom-left.
    static func origin(windowSize: CGSize, screenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: screenFrame.minX + screenFrame.width / 2 - windowSize.width / 2,
            y: screenFrame.maxY - windowSize.height
        )
    }

    /// Whether the window is where it belongs. The half-point allowance covers rounding on
    /// scaled displays, which would otherwise read as a move and be corrected for nothing.
    static func isPlaced(windowFrame: CGRect, on screenFrame: CGRect) -> Bool {
        let expected = origin(windowSize: windowFrame.size, screenFrame: screenFrame)
        return abs(windowFrame.minX - expected.x) < 0.5 && abs(windowFrame.minY - expected.y) < 0.5
    }

    /// Whether the set of displays, or the size or position of any of them, has changed.
    static func layoutChanged(from old: Set<ScreenSnapshot>?, to new: Set<ScreenSnapshot>) -> Bool {
        old != new
    }
}
