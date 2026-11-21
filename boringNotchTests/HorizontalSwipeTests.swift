//
//  HorizontalSwipeTests.swift
//  boringNotchTests
//

import CoreGraphics
import Testing

@Suite("Swipe to skip")
struct HorizontalSwipeTests {

    /// Feeds a gesture: began, then `steps` events of `dx` each, then ended. Returns what fired.
    private func swipe(_ dx: CGFloat, steps: Int = 10, dy: CGFloat = 0, inverted: Bool = true,
                       precise: Bool = true, momentumAfter: Int = 0,
                       detector: inout HorizontalSwipeDetector) -> [HorizontalSwipeDetector.Swipe] {
        var fired: [HorizontalSwipeDetector.Swipe] = []
        for i in 0..<steps {
            if let s = detector.handle(deltaX: dx, deltaY: dy, inverted: inverted, precise: precise,
                                       began: i == 0, ended: false, momentum: false) { fired.append(s) }
        }
        _ = detector.handle(deltaX: 0, deltaY: 0, inverted: inverted, precise: precise, began: false, ended: true, momentum: false)
        for _ in 0..<momentumAfter {
            if let s = detector.handle(deltaX: dx, deltaY: 0, inverted: inverted, precise: precise,
                                       began: false, ended: false, momentum: true) { fired.append(s) }
        }
        return fired
    }

    @Test("Fingers left is next, right is previous, with Natural Scrolling on")
    func naturalScrolling() {
        var d = HorizontalSwipeDetector()
        #expect(swipe(-10, detector: &d) == [.next])
        #expect(swipe(10, detector: &d) == [.previous])
    }

    @Test("The same finger movement means the same thing with Natural Scrolling off")
    func classicScrolling() {
        var d = HorizontalSwipeDetector()
        // With Natural Scrolling off the deltas are reversed relative to the fingers.
        #expect(swipe(10, inverted: false, detector: &d) == [.next])
        #expect(swipe(-10, inverted: false, detector: &d) == [.previous])
    }

    @Test("One long swipe skips once")
    func oncePerGesture() {
        var d = HorizontalSwipeDetector()
        #expect(swipe(-10, steps: 60, detector: &d) == [.next])
    }

    @Test("Momentum after the fingers lift never skips")
    func momentum() {
        var d = HorizontalSwipeDetector()
        #expect(swipe(-2, steps: 5, momentumAfter: 40, detector: &d) == [])
    }

    @Test("A short swipe does nothing")
    func short() {
        var d = HorizontalSwipeDetector()
        #expect(swipe(-4, steps: 10, detector: &d) == [])
    }

    @Test("Vertical scrolling that drifts sideways doesn't skip")
    func vertical() {
        var d = HorizontalSwipeDetector()
        #expect(swipe(-10, steps: 20, dy: 12, detector: &d) == [])
    }

    @Test("A wheel mouse never skips")
    func wheel() {
        var d = HorizontalSwipeDetector()
        #expect(swipe(-30, steps: 20, precise: false, detector: &d) == [])
    }

    @Test("Turning back mid-swipe starts the count again")
    func reversal() {
        var d = HorizontalSwipeDetector()
        var fired: [HorizontalSwipeDetector.Swipe] = []
        let deltas: [CGFloat] = [-10, -10, -10, -10, 10, 10, 10, 10, 10, 10]
        for (i, dx) in deltas.enumerated() {
            if let s = d.handle(deltaX: dx, deltaY: 0, inverted: true, precise: true,
                                began: i == 0, ended: false, momentum: false) { fired.append(s) }
        }
        #expect(fired == [.previous])
    }
}
