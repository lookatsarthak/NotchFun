//
//  BetterDisplayProtocol.swift
//  NotchFun
//

import Foundation

/// The messages NotchFun and BetterDisplay exchange, as BetterDisplay's integration guide
/// describes them (betterdisplay.pro/guide/integration/third-party-apps).
///
/// They travel as distributed notifications with a JSON string as the `object` and no
/// `userInfo`, which is what a sandboxed app is allowed to send. Pure, so it can be
/// tested without BetterDisplay installed.
enum BetterDisplayProtocol {
    static let prefix = "pro.betterdisplay.BetterDisplay"
    static let requestName = prefix + ".request"
    static let responseName = prefix + ".response"
    static let osdName = prefix + ".osd"
    static let launchedName = prefix + ".launched"
    static let terminatedName = prefix + ".terminated"
    static let bundleID = "pro.betterdisplay.BetterDisplay"

    /// BetterDisplay's own pop-up settings that NotchFun changes, and restores later.
    static let osdSettings = ["osdShowBasic", "osdShowCustom", "osdIntegrationNotification"]

    /// While connected: BetterDisplay sends its pop-up events to NotchFun and shows none
    /// of its own, so there's one brightness bar, not two.
    static let connectedValues = ["osdShowBasic": "off", "osdShowCustom": "off", "osdIntegrationNotification": "on"]

    struct Request: Codable, Equatable {
        var uuid: String
        var commands: [String]
        var parameters: [String: String?]
    }

    struct Response: Codable, Equatable {
        var uuid: String?
        var result: Bool?
        var payload: String?
    }

    /// One pop-up event from BetterDisplay.
    struct OSDEvent: Codable, Equatable {
        var displayID: Int?
        var systemIconID: Int?
        var controlTarget: String?
        var value: Double?
        var maxValue: Double?
    }

    /// `get` for one setting: `{"uuid":…,"commands":["get"],"parameters":{"osdShowBasic":null}}`.
    static func get(_ setting: String, uuid: String = UUID().uuidString) -> Request {
        Request(uuid: uuid, commands: ["get"], parameters: [setting: String?.none])
    }

    /// `set` for one setting to a value.
    static func set(_ setting: String, to value: String, uuid: String = UUID().uuidString) -> Request {
        Request(uuid: uuid, commands: ["set"], parameters: [setting: String?.some(value)])
    }

    static func encode(_ request: Request) -> String? {
        guard let data = try? JSONEncoder().encode(request) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeResponse(_ string: String) -> Response? {
        try? JSONDecoder().decode(Response.self, from: Data(string.utf8))
    }

    /// A setting's value from a `get` reply: "on" or "off", tolerating the other spellings
    /// BetterDisplay's payload might use.
    static func settingValue(from payload: String?) -> String? {
        guard let raw = payload?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else { return nil }
        switch raw {
        case "on", "true", "1", "yes": return "on"
        case "off", "false", "0", "no": return "off"
        default: return nil
        }
    }

    /// The brightness, 0...1, and the display it's for, from a pop-up event. Nil for
    /// anything that isn't a brightness event or doesn't make sense.
    static func brightness(from string: String) -> (displayID: Int?, level: Double)? {
        guard let event = try? JSONDecoder().decode(OSDEvent.self, from: Data(string.utf8)) else { return nil }
        let isBrightness = event.systemIconID == 1
            || (event.controlTarget?.localizedCaseInsensitiveContains("brightness") ?? false)
        guard isBrightness, let value = event.value, let max = event.maxValue,
              max > 0, value.isFinite, max.isFinite else { return nil }
        return (event.displayID, min(Swift.max(value / max, 0), 1))
    }
}
