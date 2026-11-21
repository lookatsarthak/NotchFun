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

    // MARK: - Choosing the output

    /// An output device, as the switcher lists it.
    struct Device: Identifiable, Equatable, Sendable {
        let id: AudioObjectID
        let name: String
        let transport: UInt32

        /// The order macOS's own Sound menu uses: the Mac first, then headphones and
        /// speakers by how they connect, then everything else.
        var rank: Int {
            switch transport {
            case kAudioDeviceTransportTypeBuiltIn: return 0
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return 1
            case kAudioDeviceTransportTypeUSB: return 2
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return 3
            case kAudioDeviceTransportTypeAirPlay: return 4
            default: return 5
            }
        }

        var symbol: String {
            switch transport {
            case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                return name.localizedCaseInsensitiveContains("airpods") ? "airpods" : "headphones"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
            case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
            default: return "hifispeaker"
            }
        }
    }

    /// Every device that can play sound, in menu order. Read when the switcher opens; there
    /// is no listener and nothing cached.
    static func outputDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id -> Device? in
            guard hasOutputStreams(id), !isHidden(id), let name = string(kAudioObjectPropertyName, of: id) else { return nil }
            return Device(id: id, name: name, transport: uint32(kAudioDevicePropertyTransportType, of: id) ?? 0)
        }
        .sorted { ($0.rank, $0.name.localizedLowercase) < ($1.rank, $1.name.localizedLowercase) }
    }

    /// Makes `id` the Mac's output, as choosing it in the Sound menu does.
    @discardableResult
    static func setOutput(_ id: AudioObjectID) -> Bool {
        var device = id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioObjectID>.size), &device
        ) == noErr
    }

    private static func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func isHidden(_ id: AudioObjectID) -> Bool {
        (uint32(kAudioDevicePropertyIsHidden, of: id) ?? 0) != 0
    }

    private static func uint32(_ selector: AudioObjectPropertySelector, of id: AudioObjectID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ selector: AudioObjectPropertySelector, of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
        return status == noErr ? value as String : nil
    }
}
