//
//  SystemAudioOutput.swift
//  NotchFun
//

import CoreAudio
import Foundation

/// The Mac's current default output device.
///
/// Both `VolumeManager` and `AccessoryBatteryManager` need to know what audio is coming
/// out of, and each had grown its own copy of this CoreAudio boilerplate. Two copies of
/// a property-address dance is two places to get the scope or the element wrong.
enum SystemAudioOutput {
    /// `kAudioObjectUnknown` when there is no default output, which callers must treat
    /// as "don't know" rather than as a device.
    static func deviceID() -> AudioObjectID {
        var deviceID = kAudioObjectUnknown
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : kAudioObjectUnknown
    }

    /// Whether the current output is a Bluetooth device.
    static func isBluetooth() -> Bool {
        let id = deviceID()
        guard id != kAudioObjectUnknown else { return false }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr
        else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth
    }

    /// The device's name as macOS knows it, for matching against a Bluetooth accessory.
    static func name() -> String? {
        let id = deviceID()
        guard id != kAudioObjectUnknown else { return nil }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return name as String
    }
}
