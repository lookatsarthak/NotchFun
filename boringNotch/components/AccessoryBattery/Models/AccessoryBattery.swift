//
//  AccessoryBattery.swift
//  NotchFun
//

import Foundation

/// A connected Bluetooth accessory and its battery.
///
/// Two sources fill this in, and they differ in what they can say:
///
/// - **The system power-source list** (`AccessoryPowerSourceParser`), for Apple and Beats
///   earbuds. It reports each bud and the case as separate parts, each with its own
///   charging state, fresh from the accessory's own broadcasts. `left`, `right` and
///   `caseLevel` come only from here.
/// - **`system_profiler`** (`AccessoryBatteryParser`), the fallback for everything else.
///   It reports left and right identically even with one bud in the case, and a case
///   level that stays long after the case has gone, so it gives one number and no parts.
struct AccessoryBattery: Equatable, Sendable, Identifiable {
    struct Part: Equatable, Sendable {
        /// 0...100.
        let level: Int
        let isCharging: Bool
    }

    /// The accessory's Bluetooth name, as macOS knows it.
    let name: String
    /// 0...100. The lower bud when there are two, because that one runs out first.
    let level: Int
    /// True when every bud that reports is charging, i.e. they are all in the case.
    var isCharging: Bool = false
    var left: Part? = nil
    var right: Part? = nil
    /// Only while a bud is charging: the case reports while it is open or holding the
    /// buds, and its last number lingers after it is shut and put away.
    var caseLevel: Part? = nil

    var id: String { name }

    /// True when there is more to say than the one number.
    var hasParts: Bool { left != nil || right != nil || caseLevel != nil }

    /// "L 80 · R 78 · Case 100", in that order, skipping parts that don't report.
    var partsSummary: String {
        var items: [String] = []
        if let left { items.append("L \(left.level)") }
        if let right { items.append("R \(right.level)") }
        if let caseLevel { items.append("Case \(caseLevel.level)") }
        return items.joined(separator: " · ")
    }

    /// For VoiceOver: "Pods: left 80 percent, right 78 percent, case 100 percent, charging".
    var spokenSummary: String {
        var items: [String] = []
        if let left { items.append("left \(left.level) percent") }
        if let right { items.append("right \(right.level) percent") }
        if let caseLevel { items.append("case \(caseLevel.level) percent") }
        if items.isEmpty { items.append("\(level) percent") }
        if isCharging { items.append("charging") }
        return "\(name) battery: " + items.joined(separator: ", ")
    }
}
