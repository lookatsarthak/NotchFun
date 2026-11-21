//
//  CameraChoiceTests.swift
//  boringNotchTests
//

import Testing

@Suite("Mirror camera choice")
struct CameraChoiceTests {
    private let phone = CameraChoice.Camera(id: "phone", kind: .continuity)
    private let builtIn = CameraChoice.Camera(id: "facetime", kind: .builtIn)
    private let usb = CameraChoice.Camera(id: "usb", kind: .external)

    @Test("The built-in camera wins over an iPhone listed first")
    func builtInFirst() {
        #expect(CameraChoice.pick(from: [phone, usb, builtIn], chosen: nil) == builtIn)
    }

    @Test("Without a built-in camera, a plugged-in one wins over an iPhone")
    func externalNext() {
        #expect(CameraChoice.pick(from: [phone, usb], chosen: nil) == usb)
    }

    @Test("An iPhone only when it's the only camera")
    func continuityLast() {
        #expect(CameraChoice.pick(from: [phone], chosen: nil) == phone)
    }

    @Test("The camera picked in Settings wins while it's connected")
    func chosen() {
        #expect(CameraChoice.pick(from: [builtIn, phone], chosen: "phone") == phone)
        #expect(CameraChoice.pick(from: [builtIn, usb], chosen: "phone") == builtIn)
    }

    @Test("No cameras, no choice")
    func none() {
        #expect(CameraChoice.pick(from: [], chosen: "usb") == nil)
    }
}
