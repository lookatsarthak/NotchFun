//
//  DragGesturePolicyTests.swift
//  boringNotchTests
//

import CoreGraphics
import Testing

@Suite("Drag gesture policy")
struct DragGesturePolicyTests {
    let start = CGPoint(x: 900, y: 300)

    @Test("A slow drag is not given up on before the source app starts it")
    func slowDragKeepsWatching() {
        // A trackpad moves a point or two per sample; the payload arrives a few points in.
        for step in 1...8 {
            let p = CGPoint(x: start.x - CGFloat(step), y: start.y + CGFloat(step))
            #expect(DragGesturePolicy.decide(pasteboardChanged: false, from: start, to: p) == .keepWatching)
        }
        let later = CGPoint(x: start.x - 9, y: start.y + 9)
        #expect(DragGesturePolicy.decide(pasteboardChanged: true, from: start, to: later) == .content)
    }

    @Test("A pasteboard change means content, at any distance")
    func changeIsContent() {
        #expect(DragGesturePolicy.decide(pasteboardChanged: true, from: start, to: start) == .content)
        #expect(DragGesturePolicy.decide(pasteboardChanged: true, from: start, to: CGPoint(x: 0, y: 0)) == .content)
    }

    @Test("A window move or text selection is dropped once past the threshold")
    func nonContentIsAbandoned() {
        let far = CGPoint(x: start.x + DragGesturePolicy.decisionDistance + 1, y: start.y)
        #expect(DragGesturePolicy.decide(pasteboardChanged: false, from: start, to: far) == .abandon)
        let edge = CGPoint(x: start.x + DragGesturePolicy.decisionDistance, y: start.y)
        #expect(DragGesturePolicy.decide(pasteboardChanged: false, from: start, to: edge) == .keepWatching)
    }
}
