//
//  AccessoryBatteryParserTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Bluetooth accessory battery parsing")
struct AccessoryBatteryParserTests {

    private func parse(_ json: String) -> [AccessoryBattery] {
        AccessoryBatteryParser.parse(Data(json.utf8))
    }

    // MARK: Fixtures
    //
    // Recorded from a real Mac running macOS 26 with AirPods paired, not hand-written.
    // The names and addresses are from that capture.

    /// AirPods connected and in use.
    private let connected = """
    {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
    "device_connected":[{"Pods":{"device_address":"F8:1E:49:D4:F5:EA",
    "device_batteryLevelCase":"96%","device_batteryLevelLeft":"80%",
    "device_batteryLevelRight":"80%","device_minorType":"Headphones",
    "device_vendorID":"0x004C"}}]}]}
    """

    /// The same AirPods a few minutes later, after they went away. macOS still reports
    /// battery for them here — and the case level has drifted from 96 to 89.
    private let disconnected = """
    {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
    "device_not_connected":[{"Pods":{"device_address":"F8:1E:49:D4:F5:EA",
    "device_batteryLevelCase":"89%","device_batteryLevelLeft":"80%",
    "device_batteryLevelRight":"80%","device_minorType":"Headphones"}},
    {"Sarthak's iPhone":{"device_address":"70:96:84:73:09:41","device_rssi":"-42"}}]}]}
    """

    /// A connected accessory that reports no battery at all.
    private let noBatteryKeys = """
    {"SPBluetoothDataType":[{"device_connected":[{"Some Headset":
    {"device_address":"11:22:33:44:55:66","device_minorType":"Headphones"}}]}]}
    """

    /// What the sandboxed process gets back for the same command: well-formed, empty.
    /// This is why the feature goes through the unsandboxed XPC helper at all.
    private let sandboxedEmpty = """
    {"SPBluetoothDataType":[{"_name":"bluetooth_information"}]}
    """

    // MARK: Tests

    @Test("Reads a connected accessory's level")
    func readsConnectedDevice() {
        let result = parse(connected)
        #expect(result.count == 1)
        #expect(result.first?.name == "Pods")
        #expect(result.first?.level == 80)
    }

    @Test("Ignores disconnected accessories, whose levels are stale")
    func ignoresDisconnected() {
        // The whole reason this rule exists: macOS reported a case level of 89% for a
        // pair that was not connected, having reported 96% while it was. Reading that
        // list would show a number that is not true now and cannot be checked.
        #expect(parse(disconnected).isEmpty)
    }

    @Test("Identical left and right yield one number, never a split")
    func neverInventsALeftRightSplit() {
        // system_profiler reports both buds identically even when one is in the case, so
        // an L/R display would be presenting a distinction the data does not contain.
        let result = parse(connected)
        #expect(result.count == 1)
        #expect(result.first?.level == 80)
    }

    @Test("Where the buds differ, the lower one is reported")
    func reportsTheLowerBud() {
        let mixed = connected.replacingOccurrences(
            of: "\"device_batteryLevelRight\":\"80%\"",
            with: "\"device_batteryLevelRight\":\"35%\""
        )
        #expect(parse(mixed).first?.level == 35)
    }

    @Test("An accessory with no battery keys produces no reading, not a zero")
    func noBatteryMeansNoReading() {
        #expect(parse(noBatteryKeys).isEmpty)
    }

    @Test("The sandboxed empty response parses to nothing rather than failing")
    func sandboxedResponseIsEmpty() {
        #expect(parse(sandboxedEmpty).isEmpty)
    }

    @Test("Junk in gives nothing out")
    func malformedInput() {
        #expect(parse("").isEmpty)
        #expect(parse("not json").isEmpty)
        #expect(parse("{}").isEmpty)
        #expect(parse("[]").isEmpty)
        #expect(parse("{\"SPBluetoothDataType\":\"a string\"}").isEmpty)
        #expect(parse("{\"SPBluetoothDataType\":[]}").isEmpty)
    }

    @Test("Percentages are parsed strictly, never coerced")
    func percentageParsing() {
        #expect(AccessoryBatteryParser.percentage("80%") == 80)
        #expect(AccessoryBatteryParser.percentage("80") == 80)
        #expect(AccessoryBatteryParser.percentage("0%") == 0)
        #expect(AccessoryBatteryParser.percentage("100%") == 100)

        // Each of these would become a believable number under a lenient parser:
        // stripping non-digits turns "-5%" into 5, and clamping turns "200%" into 100.
        #expect(AccessoryBatteryParser.percentage("-5%") == nil)
        #expect(AccessoryBatteryParser.percentage("200%") == nil)
        #expect(AccessoryBatteryParser.percentage("101") == nil)
        #expect(AccessoryBatteryParser.percentage("8 0%") == nil)
        #expect(AccessoryBatteryParser.percentage("") == nil)
        #expect(AccessoryBatteryParser.percentage("abc") == nil)
        #expect(AccessoryBatteryParser.percentage("%") == nil)
        #expect(AccessoryBatteryParser.percentage(80) == nil)
        #expect(AccessoryBatteryParser.percentage(nil) == nil)
    }
}
