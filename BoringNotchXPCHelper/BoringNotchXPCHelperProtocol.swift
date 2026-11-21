//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Bluetooth accessory battery (performed by the helper)
    //
    // Returns raw `system_profiler -json SPBluetoothDataType` stdout, or nil when the
    // tool could not be run, timed out, or produced nothing. The app parses it; the
    // helper deliberately does not, so the parser can live in a testable file and this
    // unsandboxed process keeps doing as little as possible.
    //
    // NSData rather than NSDictionary on purpose: a collection-typed reply argument
    // needs NSXPCInterface.setClasses(_:for:argumentIndex:ofReply:), and forgetting it
    // fails at runtime with an empty reply - indistinguishable from "nothing connected".
    func bluetoothProfileJSON(with reply: @escaping (NSData?) -> Void)

    // Text in a copied image (performed by the helper)
    //
    // Apple's text recognition takes about 140 MB while it runs; doing it here keeps
    // that out of the app. Returns the recognised lines joined by newlines, or nil when
    // there's no text or the image can't be read.
    func recognizeText(in imageData: NSData, with reply: @escaping (NSString?) -> Void)
}
