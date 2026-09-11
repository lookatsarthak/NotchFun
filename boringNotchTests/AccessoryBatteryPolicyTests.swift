//
//  AccessoryBatteryPolicyTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Accessory battery banner visibility")
struct AccessoryBatteryPolicyTests {

    /// Every field defaults to the case where the banner *should* show, so each test
    /// below flips exactly one thing and reads as a sentence.
    private func showing(
        hasReading: Bool = true,
        settingEnabled: Bool = true,
        bannerRequested: Bool = true,
        notchIsClosed: Bool = true,
        hiddenForFullscreen: Bool = false,
        powerBannerIsShowing: Bool = false,
        inlineHUDIsShowing: Bool = false
    ) -> Bool {
        AccessoryBatteryPolicy.showsBanner(
            .init(
                hasReading: hasReading,
                settingEnabled: settingEnabled,
                bannerRequested: bannerRequested,
                notchIsClosed: notchIsClosed,
                hiddenForFullscreen: hiddenForFullscreen,
                powerBannerIsShowing: powerBannerIsShowing,
                inlineHUDIsShowing: inlineHUDIsShowing
            )
        )
    }

    @Test("Shown when an accessory connects and nothing else needs the notch")
    func shownOnConnect() {
        #expect(showing())
    }

    @Test("Hidden when there is no reading to show")
    func hiddenWithoutAReading() {
        // Covers a dropped XPC connection as well as a genuinely absent accessory: the
        // manager reports no reading for both, so neither can render an empty banner.
        #expect(!showing(hasReading: false))
    }

    @Test("Hidden when the user turned it off")
    func respectsTheSetting() {
        #expect(!showing(settingEnabled: false))
    }

    @Test("Not shown unprompted")
    func onlyOnRequest() {
        // Status, not a standing claim on the notch. Without a connect or an open, a
        // known battery level is not news.
        #expect(!showing(bannerRequested: false))
    }

    @Test("Hidden while the notch is open, where the header shows it instead")
    func hiddenWhileOpen() {
        #expect(!showing(notchIsClosed: false))
    }

    @Test("Hidden while the notch is hidden for a fullscreen app")
    func hiddenInFullscreen() {
        #expect(!showing(hiddenForFullscreen: true))
    }

    @Test("Yields to the Mac's own power banner")
    func yieldsToPower() {
        // A power-source change is something nothing else announces.
        #expect(!showing(powerBannerIsShowing: true))
    }

    @Test("Yields to a volume or brightness HUD")
    func yieldsToTheHUD() {
        // The reason this ranks below the HUD: connecting earbuds is followed almost
        // immediately by reaching for the volume keys, and winning here would eat the
        // feedback for that gesture.
        #expect(!showing(inlineHUDIsShowing: true))
    }
}
