//
//  CaffeineIndicatorPolicyTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Caffeine notch indicator policy")
struct CaffeineIndicatorPolicyTests {
    /// Caffeine on, notch closed, nothing else competing.
    private func showing(
        isActive: Bool = true,
        settingEnabled: Bool = true,
        notchIsClosed: Bool = true,
        hiddenForFullscreen: Bool = false,
        bannerIsShowing: Bool = false,
        inlineHUDIsShowing: Bool = false
    ) -> Bool {
        CaffeineIndicatorPolicy.showsIndicator(
            .init(
                isActive: isActive,
                settingEnabled: settingEnabled,
                notchIsClosed: notchIsClosed,
                hiddenForFullscreen: hiddenForFullscreen,
                bannerIsShowing: bannerIsShowing,
                inlineHUDIsShowing: inlineHUDIsShowing
            )
        )
    }

    @Test("Shown while caffeine is on and nothing else needs the notch")
    func shownWhenActive() {
        #expect(showing())
    }

    @Test("Hidden whenever caffeine is off")
    func hiddenWhenInactive() {
        #expect(!showing(isActive: false))
    }

    @Test("Hidden when the user turned the indicator off")
    func respectsSetting() {
        #expect(!showing(settingEnabled: false))
    }

    @Test("Hidden while the notch is open, where the header button already shows it")
    func hiddenWhenOpen() {
        #expect(!showing(notchIsClosed: false))
    }

    @Test("Hidden while the notch is hidden for a fullscreen app")
    func hiddenInFullscreen() {
        #expect(!showing(hiddenForFullscreen: true))
    }

    @Test("Yields to a volume or brightness HUD")
    func yieldsToHUD() {
        // The whole point of the ordering: a key the user just pressed wins.
        #expect(!showing(inlineHUDIsShowing: true))
    }

    @Test("Yields to a battery, caffeine or download banner")
    func yieldsToBanner() {
        #expect(!showing(bannerIsShowing: true))
    }

    @Test("Comes back once the thing that displaced it finishes")
    func returnsAfterTransient() {
        #expect(!showing(inlineHUDIsShowing: true))
        #expect(showing(inlineHUDIsShowing: false))
        #expect(!showing(bannerIsShowing: true))
        #expect(showing(bannerIsShowing: false))
    }

    @Test("Being off beats every other reason to show it")
    func inactiveDominates() {
        #expect(!showing(isActive: false, settingEnabled: true))
        #expect(!showing(isActive: false, bannerIsShowing: false, inlineHUDIsShowing: false))
    }
}
