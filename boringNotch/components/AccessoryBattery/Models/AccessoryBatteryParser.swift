//
//  AccessoryBatteryParser.swift
//  boringNotch
//

import Foundation

/// Turns raw `system_profiler -json SPBluetoothDataType` bytes into battery readings.
///
/// This lives in the app rather than in the XPC helper on purpose. The helper is
/// unsandboxed — it exists because the App Sandbox returns an empty result for
/// `system_profiler` no matter what entitlements are set — so it should do as little as
/// possible, and its folder is a synchronized group that a second target cannot easily
/// compile from. Keeping the parsing here means it is Foundation-only and unit-testable.
///
/// Every rule below fails closed. `system_profiler`'s JSON keys are not API, so anything
/// unrecognised produces no reading at all rather than a plausible-looking wrong number.
enum AccessoryBatteryParser {

    static func parse(_ data: Data) -> [AccessoryBattery] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["SPBluetoothDataType"] as? [[String: Any]],
            let section = sections.first
        else { return [] }

        // Only `device_connected`. The disconnected list carries battery levels too, and
        // they are stale by definition — a pair that had been put away still reported a
        // case level here, several points off what it read while connected.
        guard let connected = section["device_connected"] as? [[String: Any]] else { return [] }

        return connected.compactMap { entry in
            // Each element is a single-key dictionary keyed by the device's name.
            guard
                let name = entry.keys.first,
                let info = entry[name] as? [String: Any],
                let level = level(from: info)
            else { return nil }
            return AccessoryBattery(name: name, level: level)
        }
    }

    /// The single level for one device.
    ///
    /// Earbuds first, then the single-battery keys other accessories use. Returns nil
    /// rather than a default when nothing parses — a keyboard reports no battery keys at
    /// all, and it should produce no reading rather than a zero.
    private static func level(from info: [String: Any]) -> Int? {
        let left = percentage(info["device_batteryLevelLeft"])
        let right = percentage(info["device_batteryLevelRight"])

        // The lower of the pair. Not labelled L/R: see AccessoryBattery for why the split
        // is not real.
        if let both = [left, right].compactMap({ $0 }).min() { return both }

        return percentage(info["device_batteryLevel"])
            ?? percentage(info["device_batteryLevelMain"])
    }

    /// Parses `"80%"` and `"80"`; rejects everything else.
    ///
    /// Deliberately strict rather than lenient. Stripping non-digits would turn `"-5%"`
    /// into 5, and clamping would turn `"200%"` into 100 — both of which convert a parse
    /// failure into a number the UI would happily display as real.
    static func percentage(_ raw: Any?) -> Int? {
        guard let string = raw as? String else { return nil }
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("%") { text = String(text.dropLast()) }
        guard
            !text.isEmpty,
            text.allSatisfy({ $0.isASCII && $0.isNumber }),
            let value = Int(text),
            (0...100).contains(value)
        else { return nil }
        return value
    }
}
