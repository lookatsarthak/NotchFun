//
//  BetterDisplayProtocolTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("BetterDisplay messages")
struct BetterDisplayProtocolTests {

    @Test("A get request names the setting with a null value, as the guide shows")
    func getRequest() throws {
        let json = try #require(BetterDisplayProtocol.encode(BetterDisplayProtocol.get("osdShowBasic", uuid: "u1")))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["uuid"] as? String == "u1")
        #expect(object["commands"] as? [String] == ["get"])
        let parameters = try #require(object["parameters"] as? [String: Any])
        #expect(parameters["osdShowBasic"] is NSNull)
    }

    @Test("A set request carries the value")
    func setRequest() throws {
        let json = try #require(BetterDisplayProtocol.encode(BetterDisplayProtocol.set("osdShowBasic", to: "off", uuid: "u2")))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect((object["parameters"] as? [String: Any])?["osdShowBasic"] as? String == "off")
    }

    @Test("Replies decode, and setting values are read leniently")
    func replies() {
        let response = BetterDisplayProtocol.decodeResponse(#"{"uuid":"u1","result":true,"payload":"on"}"#)
        #expect(response == .init(uuid: "u1", result: true, payload: "on"))
        #expect(BetterDisplayProtocol.settingValue(from: " On\n") == "on")
        #expect(BetterDisplayProtocol.settingValue(from: "false") == "off")
        #expect(BetterDisplayProtocol.settingValue(from: "maybe") == nil)
        #expect(BetterDisplayProtocol.settingValue(from: nil) == nil)
        #expect(BetterDisplayProtocol.decodeResponse("not json") == nil)
    }

    @Test("Brightness events give a 0–1 level and the display")
    func brightnessEvents() throws {
        let event = try #require(BetterDisplayProtocol.brightness(
            from: #"{"displayID":4,"systemIconID":1,"controlTarget":"combinedBrightness","value":32,"maxValue":64}"#))
        #expect(event.displayID == 4)
        #expect(event.level == 0.5)
        let byTarget = BetterDisplayProtocol.brightness(from: #"{"controlTarget":"hardwareBrightness","value":0.8,"maxValue":1}"#)
        #expect(byTarget?.level == 0.8)
    }

    @Test("Other events and nonsense are ignored")
    func ignored() {
        #expect(BetterDisplayProtocol.brightness(from: #"{"systemIconID":3,"controlTarget":"volume","value":5,"maxValue":10}"#) == nil)
        #expect(BetterDisplayProtocol.brightness(from: #"{"systemIconID":1,"value":5,"maxValue":0}"#) == nil)
        #expect(BetterDisplayProtocol.brightness(from: #"{"systemIconID":1,"value":5}"#) == nil)
        #expect(BetterDisplayProtocol.brightness(from: "garbage") == nil)
        #expect(BetterDisplayProtocol.brightness(from: #"{"systemIconID":1,"value":90,"maxValue":64}"#)?.level == 1)
    }
}
