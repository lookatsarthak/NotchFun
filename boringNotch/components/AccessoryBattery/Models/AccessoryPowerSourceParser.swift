//
//  AccessoryPowerSourceParser.swift
//  NotchFun
//

import Foundation

/// Turns the system's accessory power sources into battery readings.
///
/// The input is one dictionary per power source, as `IOPSGetPowerSourceDescription`
/// returns them for the accessory list (what `pmset -g accps` prints). For a pair of
/// AirPods there are two entries sharing a `Group Identifier`:
///
/// - the buds, `Accessory Category` "Headset", with a `Combined Parts` array holding one
///   entry per bud (`Part Identifier` "Left" or "Right");
/// - the case, `Accessory Category` "Audio Battery Case".
///
/// Older or other headsets may list the buds as separate entries instead of combined
/// parts, and headphones with one battery have no parts at all. All three shapes parse.
///
/// Pure and Foundation-only so it can be tested. The keys are not documented API, so
/// anything unrecognised produces no reading rather than a guessed one.
enum AccessoryPowerSourceParser {

    static func parse(_ sources: [[String: Any]]) -> [AccessoryBattery] {
        let accessories = sources.filter { ($0["Type"] as? String) == "Accessory Source" }

        // Keep the order the system gave, so results are stable from call to call.
        var order: [String] = []
        var groups: [String: [[String: Any]]] = [:]
        for source in accessories {
            guard let key = groupKey(source) else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(source)
        }
        return order.compactMap { reading(from: groups[$0] ?? []) }
    }

    private static func groupKey(_ source: [String: Any]) -> String? {
        if let group = source["Group Identifier"] as? String, !group.isEmpty { return group }
        if let id = source["Accessory Identifier"] as? String, !id.isEmpty { return id }
        return name(source)
    }

    private static func reading(from group: [[String: Any]]) -> AccessoryBattery? {
        var left: AccessoryBattery.Part?
        var right: AccessoryBattery.Part?
        var caseLevel: AccessoryBattery.Part?
        var single: AccessoryBattery.Part?
        var deviceName: String?
        var isAudio = false

        for source in group {
            let category = source["Accessory Category"] as? String ?? ""
            if isCase(source, category: category) {
                caseLevel = part(source) ?? caseLevel
                isAudio = true
                continue
            }
            if isAudioCategory(category) { isAudio = true }

            /// Files one bud or case under its part; false if it names no part.
            func file(_ item: [String: Any]) -> Bool {
                switch (item["Part Identifier"] as? String)?.lowercased() {
                case "left": left = part(item) ?? left
                case "right": right = part(item) ?? right
                case "case": caseLevel = part(item) ?? caseLevel
                default: return false
                }
                isAudio = true
                return true
            }

            if let combined = source["Combined Parts"] as? [[String: Any]] {
                combined.forEach { _ = file($0) }
            } else if !file(source) {
                single = part(source) ?? single
            }
            if deviceName == nil { deviceName = name(source) }
        }

        // A keyboard, mouse or trackpad also reports here. Only audio accessories belong
        // in the earbud slot.
        guard isAudio else { return nil }

        let buds = [left, right].compactMap { $0 }
        let headline: AccessoryBattery.Part?
        if let lowest = buds.min(by: { $0.level < $1.level }) {
            headline = .init(level: lowest.level, isCharging: buds.allSatisfy(\.isCharging))
        } else {
            headline = single
        }
        // A case on its own is not something you are listening through.
        guard let headline, let deviceName = deviceName ?? caseName(group) else { return nil }

        // The case reports while open or holding the buds and lingers afterwards, so it
        // is shown only while a bud says it is charging, which means it is in the case.
        let budsInCase = buds.contains(where: \.isCharging)

        return AccessoryBattery(
            name: deviceName,
            level: headline.level,
            isCharging: headline.isCharging,
            left: left,
            right: right,
            caseLevel: budsInCase ? caseLevel : nil
        )
    }

    private static func isCase(_ source: [String: Any], category: String) -> Bool {
        category.localizedCaseInsensitiveContains("case")
            || (source["Part Identifier"] as? String)?.lowercased() == "case"
    }

    private static func isAudioCategory(_ category: String) -> Bool {
        ["headset", "headphone", "earbud", "audio", "speaker"].contains {
            category.localizedCaseInsensitiveContains($0)
        }
    }

    private static func name(_ source: [String: Any]) -> String? {
        guard let name = (source["Name"] as? String)?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty else { return nil }
        return name
    }

    /// The buds' name from a case-only group, without its " Case" suffix.
    private static func caseName(_ group: [[String: Any]]) -> String? {
        guard let name = group.compactMap(name).first else { return nil }
        if name.hasSuffix(" Case") { return String(name.dropLast(5)) }
        return name
    }

    /// One battery, or nil if it doesn't report a sane level.
    private static func part(_ source: [String: Any]) -> AccessoryBattery.Part? {
        if let present = source["Is Present"] as? Bool, !present { return nil }
        if let present = source["Is Present"] as? Int, present == 0 { return nil }
        guard let current = integer(source["Current Capacity"]) else { return nil }
        let max = integer(source["Max Capacity"]) ?? 100
        guard max > 0 else { return nil }
        let level = max == 100 ? current : Int((Double(current) / Double(max) * 100).rounded())
        guard (0...100).contains(level) else { return nil }
        return .init(level: level, isCharging: boolean(source["Is Charging"]))
    }

    private static func integer(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }
}
