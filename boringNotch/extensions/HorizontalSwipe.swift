//
//  HorizontalSwipe.swift
//  NotchFun
//

import AppKit
import SwiftUI

/// Turns two-finger horizontal scrolling into at most one skip per gesture.
///
/// Pure, so the rules can be tested without a trackpad:
/// - **Direction** follows the fingers whatever the Natural Scrolling setting: a swipe
///   left is "next", as on an iPhone's mini player.
/// - **Horizontal only.** Each event must be mostly sideways, so a vertical scroll that
///   drifts never skips.
/// - **Once per gesture.** After firing it waits for the fingers to lift, so one long
///   swipe can't skip three tracks. Momentum after the lift is ignored too.
/// - **Trackpad and Magic Mouse only**, which report gesture phases.
struct HorizontalSwipeDetector: Sendable {
    enum Swipe: Equatable, Sendable { case next, previous }

    /// Points of finger travel to fire. A deliberate swipe on a trackpad is 60–150.
    var threshold: CGFloat = 50

    private var accumulated: CGFloat = 0
    private var fired = false

    /// One scroll event.
    /// - Parameters:
    ///   - deltaX, deltaY: `scrollingDeltaX` and `scrollingDeltaY`.
    ///   - inverted: `isDirectionInvertedFromDevice` (Natural Scrolling on).
    ///   - began: a new touch gesture started (`phase == .began` or `.mayBegin`).
    ///   - ended: the fingers lifted or the gesture was cancelled.
    ///   - momentum: a momentum event, after the lift.
    mutating func handle(deltaX: CGFloat, deltaY: CGFloat, inverted: Bool, precise: Bool,
                         began: Bool, ended: Bool, momentum: Bool) -> Swipe? {
        if began { accumulated = 0; fired = false }
        if ended { accumulated = 0; fired = false; return nil }
        // Trackpads and Magic Mouse only. A wheel has no phases, so there would be no
        // "fingers lifted" to end a gesture on.
        guard precise, !momentum, !fired else { return nil }
        // Mostly sideways, or it doesn't count.
        guard abs(deltaX) >= 1.5 * abs(deltaY), deltaX != 0 else { return nil }

        // Finger travel: with Natural Scrolling the deltas already follow the fingers.
        let finger = inverted ? deltaX : -deltaX
        // A change of direction starts the count again.
        if (finger > 0) != (accumulated > 0), accumulated != 0 { accumulated = 0 }
        accumulated += finger

        guard abs(accumulated) >= threshold else { return nil }
        fired = true
        return accumulated < 0 ? .next : .previous
    }
}

extension View {
    /// Calls `action` once per two-finger horizontal swipe over this view while `enabled`.
    func horizontalSwipe(enabled: Bool, action: @escaping (HorizontalSwipeDetector.Swipe) -> Void) -> some View {
        background {
            if enabled { HorizontalSwipeMonitor(action: action) }
        }
    }
}

/// One local scroll monitor per view that uses it, removed with the view, and only
/// listening to events whose pointer is inside the view. No timers and no tasks per event:
/// the gesture's end comes from the event's own phase.
private struct HorizontalSwipeMonitor: NSViewRepresentable {
    let action: (HorizontalSwipeDetector.Swipe) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    @MainActor final class Coordinator {
        var action: (HorizontalSwipeDetector.Swipe) -> Void
        private var detector = HorizontalSwipeDetector()
        private var monitor: Any?

        init(action: @escaping (HorizontalSwipeDetector.Swipe) -> Void) {
            self.action = action
        }

        func install(on view: NSView) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil))
                else { return event }
                let swipe = self.detector.handle(
                    deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                    inverted: event.isDirectionInvertedFromDevice,
                    precise: event.hasPreciseScrollingDeltas,
                    began: event.phase == .began || event.phase == .mayBegin,
                    ended: event.phase == .ended || event.phase == .cancelled,
                    momentum: event.momentumPhase != []
                )
                if let swipe { self.action(swipe) }
                return event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
