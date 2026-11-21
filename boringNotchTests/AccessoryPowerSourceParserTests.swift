//
//  AccessoryPowerSourceParserTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Accessory power sources (AirPods left, right and case)")
struct AccessoryPowerSourceParserTests {

    // MARK: Fixtures
    //
    // The shape recorded on macOS 27.2 from `IOPSCopyPowerSourcesByType` with AirPods in
    // their case, trimmed to the keys the parser reads. Identifiers are made up.

    private func bud(_ side: String, _ level: Int, charging: Bool, present: Bool = true) -> [String: Any] {
        [
            "Type": "Accessory Source", "Accessory Category": "Headset", "Name": "Pods",
            "Part Identifier": side, "Current Capacity": level, "Max Capacity": 100,
            "Is Charging": charging ? 1 : 0, "Is Present": present ? 1 : 0,
            "Group Identifier": "GROUP-1",
        ]
    }

    private func headset(left: Int, right: Int, charging: Bool) -> [String: Any] {
        [
            "Type": "Accessory Source", "Accessory Category": "Headset", "Name": "Pods",
            "Part Identifier": "Combined", "Current Capacity": min(left, right), "Max Capacity": 100,
            "Is Charging": charging ? 1 : 0, "Is Present": 1, "Group Identifier": "GROUP-1",
            "Combined Parts": [bud("Left", left, charging: charging), bud("Right", right, charging: charging)],
        ]
    }

    private func batteryCase(_ level: Int, charging: Bool = false) -> [String: Any] {
        [
            "Type": "Accessory Source", "Accessory Category": "Audio Battery Case", "Name": "Pods Case",
            "Current Capacity": level, "Max Capacity": 100, "Is Charging": charging ? 1 : 0,
            "Is Present": 1, "Group Identifier": "GROUP-1",
        ]
    }

    // MARK: AirPods

    @Test("Buds in the case: left, right, case and charging")
    func budsInCase() throws {
        let readings = AccessoryPowerSourceParser.parse([batteryCase(100, charging: true), headset(left: 80, right: 78, charging: true)])
        let pods = try #require(readings.first)
        #expect(readings.count == 1)
        #expect(pods.name == "Pods")
        #expect(pods.level == 78)
        #expect(pods.isCharging)
        #expect(pods.left == .init(level: 80, isCharging: true))
        #expect(pods.right == .init(level: 78, isCharging: true))
        #expect(pods.caseLevel == .init(level: 100, isCharging: true))
        #expect(pods.partsSummary == "L 80 · R 78 · Case 100")
    }

    @Test("Buds in your ears: the case's lingering number is not shown")
    func budsOut() throws {
        let pods = try #require(AccessoryPowerSourceParser.parse([batteryCase(64), headset(left: 55, right: 61, charging: false)]).first)
        #expect(pods.level == 55)
        #expect(!pods.isCharging)
        #expect(pods.caseLevel == nil)
        #expect(pods.partsSummary == "L 55 · R 61")
    }

    @Test("One bud in the case: the headline isn't 'charging'")
    func oneBudCharging() throws {
        var pods = headset(left: 40, right: 90, charging: false)
        pods["Combined Parts"] = [bud("Left", 40, charging: false), bud("Right", 90, charging: true)]
        let reading = try #require(AccessoryPowerSourceParser.parse([pods, batteryCase(70)]).first)
        #expect(reading.level == 40)
        #expect(!reading.isCharging)
        #expect(reading.caseLevel?.level == 70)
    }

    @Test("A bud that isn't present is left out")
    func absentBud() throws {
        var pods = headset(left: 40, right: 90, charging: false)
        pods["Combined Parts"] = [bud("Left", 40, charging: false), bud("Right", 0, charging: false, present: false)]
        let reading = try #require(AccessoryPowerSourceParser.parse([pods]).first)
        #expect(reading.left?.level == 40)
        #expect(reading.right == nil)
        #expect(reading.partsSummary == "L 40")
    }

    @Test("Buds listed as separate entries instead of combined parts")
    func separateEntries() throws {
        let reading = try #require(AccessoryPowerSourceParser.parse([bud("Left", 30, charging: false), bud("Right", 35, charging: false)]).first)
        #expect(reading.name == "Pods")
        #expect(reading.level == 30)
        #expect(reading.left?.level == 30)
        #expect(reading.right?.level == 35)
    }

    // MARK: Other accessories

    @Test("Single-battery headphones give one number and no parts")
    func singleBattery() throws {
        let max: [String: Any] = [
            "Type": "Accessory Source", "Accessory Category": "Headphones", "Name": "Max",
            "Current Capacity": 42, "Max Capacity": 100, "Is Charging": 0, "Accessory Identifier": "A-2",
        ]
        let reading = try #require(AccessoryPowerSourceParser.parse([max]).first)
        #expect(reading.level == 42)
        #expect(!reading.hasParts)
    }

    @Test("A keyboard or mouse never becomes an audio reading")
    func nonAudio() {
        let keyboard: [String: Any] = [
            "Type": "Accessory Source", "Accessory Category": "Keyboard", "Name": "Keyboard",
            "Current Capacity": 90, "Max Capacity": 100, "Accessory Identifier": "K-1",
        ]
        #expect(AccessoryPowerSourceParser.parse([keyboard]).isEmpty)
    }

    @Test("A case on its own is not something you listen through")
    func caseOnly() {
        #expect(AccessoryPowerSourceParser.parse([batteryCase(50)]).isEmpty)
    }

    @Test("The Mac's own battery and unreadable levels are ignored")
    func rejects() {
        let macBattery: [String: Any] = ["Type": "InternalBattery", "Name": "InternalBattery-0", "Current Capacity": 11]
        var broken = headset(left: 80, right: 78, charging: false)
        broken["Combined Parts"] = [bud("Left", 140, charging: false)]
        broken["Current Capacity"] = -1
        #expect(AccessoryPowerSourceParser.parse([macBattery, broken]).isEmpty)
    }

    @Test("Two pairs stay apart and keep the system's order")
    func twoPairs() {
        var other = headset(left: 10, right: 12, charging: false)
        other["Name"] = "Other"
        other["Group Identifier"] = "GROUP-2"
        let readings = AccessoryPowerSourceParser.parse([headset(left: 80, right: 78, charging: false), other])
        #expect(readings.map(\.name) == ["Pods", "Other"])
    }
}
