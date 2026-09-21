//
//  AccessoryBattery.swift
//  NotchFun
//

import Foundation

/// A connected Bluetooth accessory and the one battery number worth showing for it.
///
/// One number, deliberately. `system_profiler` reports `device_batteryLevelLeft` and
/// `device_batteryLevelRight` identically even when a single earbud is in your ear and
/// the other is in the case — so a left/right split would be presenting a distinction
/// that the data does not actually contain. Where the two differ, the lower one is what
/// matters, because that is the one about to run out.
///
/// There is no case level here either. `device_batteryLevelCase` is a last-known value
/// that keeps being reported long after the case is out of range — a disconnected pair on
/// this machine still reported one — and nothing in the payload says whether it is fresh.
/// Showing a stale number as a live one is worse than showing nothing.
struct AccessoryBattery: Equatable, Sendable, Identifiable {
    /// The accessory's Bluetooth name, as macOS knows it.
    let name: String
    /// 0...100.
    let level: Int

    var id: String { name }
}
