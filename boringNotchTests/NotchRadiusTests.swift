//
//  NotchRadiusTests.swift
//  boringNotchTests
//

import CoreGraphics
import Foundation
import Testing

@Suite("Concentric corner radii")
struct NotchRadiusTests {

    @Test("An inner shape's radius is the outer one less the gap")
    func sharesACentre() {
        // The whole point: the inner corner and the outer corner sweep around the same
        // point, which is what stops the inner one looking tighter than the gap.
        #expect(NotchRadius.concentric(outer: 16, inset: 4) == 12)
        #expect(NotchRadius.concentric(outer: 20, inset: 8) == 12)
    }

    @Test("No inset means no change")
    func zeroInset() {
        #expect(NotchRadius.concentric(outer: 16, inset: 0) == 16)
    }

    @Test("A gap wider than the radius does not produce a square or negative corner")
    func clampsAtTheBottom() {
        // A negative radius is a crash or a rendering artifact depending on the shape,
        // and a hard zero next to a round container reads as a bug rather than a choice.
        #expect(NotchRadius.concentric(outer: 8, inset: 20) == 1)
        #expect(NotchRadius.concentric(outer: 8, inset: 8) == 1)
        #expect(NotchRadius.concentric(outer: 12, inset: 11) == 1)
    }

    @Test("Nesting twice stays consistent")
    func nestsTransitively() {
        // panel 16, inner padding 4, then a tile inside that with padding 2.
        let inner = NotchRadius.concentric(outer: NotchRadius.panel, inset: 4)
        let innermost = NotchRadius.concentric(outer: inner, inset: 2)
        #expect(inner == 12)
        #expect(innermost == 10)
    }

    @Test("The tokens are ordered from smallest control to largest container")
    func tokenOrdering() {
        #expect(NotchRadius.control < NotchRadius.item)
        #expect(NotchRadius.item < NotchRadius.panel)
    }
}
