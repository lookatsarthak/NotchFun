//
//  NotchPlacementTests.swift
//  boringNotchTests
//

import CoreGraphics
import Testing

/// The notch window hangs from the top of its screen. When mirroring changed a display's
/// size, it could be left at the old top edge, which is the middle of the new screen.
@Suite("Notch placement")
struct NotchPlacementTests {
    private let window = CGSize(width: 640, height: 210)
    private let laptop = CGRect(x: 0, y: 0, width: 1470, height: 956)
    /// The same display once mirroring has moved it to a TV's resolution.
    private let mirrored = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test("Centred and hanging from the top edge")
    func origin() {
        #expect(NotchPlacement.origin(windowSize: window, screenFrame: laptop) == CGPoint(x: 415, y: 746))
    }

    @Test("A display to the side or above keeps its own offset")
    func offsetDisplay() {
        let beside = CGRect(x: 1470, y: 200, width: 2560, height: 1440)
        #expect(NotchPlacement.origin(windowSize: window, screenFrame: beside) == CGPoint(x: 2430, y: 1430))
    }

    @Test("A window left at the old top edge is recognised as misplaced (the bug this guards)")
    func staleWindow() {
        let origin = NotchPlacement.origin(windowSize: window, screenFrame: laptop)
        let frame = CGRect(origin: origin, size: window)
        #expect(NotchPlacement.isPlaced(windowFrame: frame, on: laptop))
        #expect(!NotchPlacement.isPlaced(windowFrame: frame, on: mirrored))
    }

    @Test("Sub-point rounding doesn't count as a move")
    func rounding() {
        let frame = CGRect(x: 415.25, y: 745.75, width: 640, height: 210)
        #expect(NotchPlacement.isPlaced(windowFrame: frame, on: laptop))
    }

    @Test("The same display at a new size counts as a change")
    func sameDisplayNewSize() {
        let before: Set = [ScreenSnapshot(uuid: "A", frame: laptop)]
        let after: Set = [ScreenSnapshot(uuid: "A", frame: mirrored)]
        #expect(NotchPlacement.layoutChanged(from: before, to: after))
    }

    @Test("An unchanged layout doesn't, whatever order the displays come in")
    func unchanged() {
        let second = CGRect(x: 1470, y: 0, width: 1920, height: 1080)
        let before: Set = [ScreenSnapshot(uuid: "A", frame: laptop), ScreenSnapshot(uuid: "B", frame: second)]
        let after: Set = [ScreenSnapshot(uuid: "B", frame: second), ScreenSnapshot(uuid: "A", frame: laptop)]
        #expect(!NotchPlacement.layoutChanged(from: before, to: after))
    }

    @Test("Displays appearing, going, and the first look all count as changes")
    func displaysComeAndGo() {
        let one: Set = [ScreenSnapshot(uuid: "A", frame: laptop)]
        let two: Set = [ScreenSnapshot(uuid: "A", frame: laptop), ScreenSnapshot(uuid: "B", frame: mirrored)]
        #expect(NotchPlacement.layoutChanged(from: one, to: two))
        #expect(NotchPlacement.layoutChanged(from: two, to: one))
        #expect(NotchPlacement.layoutChanged(from: nil, to: one))
    }

    @Test("Rechecks run in order and well after the change has settled")
    func settleDelays() {
        #expect(NotchPlacement.settleDelays == NotchPlacement.settleDelays.sorted())
        #expect((NotchPlacement.settleDelays.last ?? 0) >= 2)
    }
}
