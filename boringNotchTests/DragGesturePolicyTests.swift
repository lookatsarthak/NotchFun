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
            #expect(DragGesturePolicy.decide(pasteboardChanged: false, from: start, to: p, elapsed: Double(step) * 0.016) == .keepWatching)
        }
        let later = CGPoint(x: start.x - 9, y: start.y + 9)
        #expect(DragGesturePolicy.decide(pasteboardChanged: true, from: start, to: later, elapsed: 0.15) == .content)
    }

    @Test("A pasteboard change means content, at any distance")
    func changeIsContent() {
        #expect(DragGesturePolicy.decide(pasteboardChanged: true, from: start, to: start, elapsed: 0) == .content)
        #expect(DragGesturePolicy.decide(pasteboardChanged: true, from: start, to: CGPoint(x: 0, y: 0), elapsed: 5) == .content)
    }

    @Test("A window move or text selection is dropped once past the distance and the moment")
    func nonContentIsAbandoned() {
        let far = CGPoint(x: start.x + DragGesturePolicy.decisionDistance + 1, y: start.y)
        let late = DragGesturePolicy.decisionTime + 0.05
        #expect(DragGesturePolicy.decide(pasteboardChanged: false, from: start, to: far, elapsed: late) == .abandon)
        let edge = CGPoint(x: start.x + DragGesturePolicy.decisionDistance, y: start.y)
        #expect(DragGesturePolicy.decide(pasteboardChanged: false, from: start, to: edge, elapsed: late) == .keepWatching)
    }

    @Test("A screenshot thumbnail's fast flick is still caught when its payload arrives late")
    func lateSourceIsNotAbandoned() {
        // The thumbnail writes a file before it publishes the drag: the pointer is already
        // well past the distance a few samples in, with nothing on the pasteboard yet.
        // Measured: the payload arrived 0.255 s after the first movement, ~75 pt away.
        let flick = CGPoint(x: start.x - 49, y: start.y - 58)
        #expect(DragGesturePolicy.decide(pasteboardChanged: false, from: start, to: flick, elapsed: 0.12) == .keepWatching)
        #expect(DragGesturePolicy.decide(pasteboardChanged: false, from: start, to: flick, elapsed: 0.6) == .keepWatching)
        #expect(DragGesturePolicy.decide(pasteboardChanged: true, from: start, to: flick, elapsed: 0.255) == .content)
    }
}
