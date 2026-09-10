//
//  MusicLiveActivityMetricsTests.swift
//  boringNotchTests
//

import CoreGraphics
import Foundation
import Testing

@Suite("Closed-notch music slot sizing")
struct MusicLiveActivityMetricsTests {

    private func metrics(
        height: CGFloat = 32,
        compact: Bool = false,
        gesture: CGFloat = 0
    ) -> MusicLiveActivityMetrics.Metrics {
        MusicLiveActivityMetrics.metrics(
            .init(closedNotchHeight: height, compact: compact, gestureProgress: gesture)
        )
    }

    @Test("Standard mode reproduces the row the notch has always drawn")
    func pinsExistingBehaviour() {
        // The pinning test. Before this type existed the view body computed
        // `max(0, effectiveClosedNotchHeight - 12)` inline, and the HStack took SwiftUI's
        // default spacing, measured at 8pt. On a 32pt notch that is a 20/20 pair of slots
        // and 56pt added. If this goes red, the closed notch has visibly changed for
        // every existing user.
        let m = metrics()
        #expect(m.artSize == 20)
        #expect(m.spectrumWidth == 20)
        #expect(m.spectrumHeight == 20)
        #expect(m.spacing == 8)
        #expect(m.addedWidth == 56)
    }

    @Test("Added width corrects the hover chin's old 4pt overshoot")
    func correctsTheChinGuess() {
        // `computedChinWidth` used to add a bare `+ 20` for the two HStack gaps, but the
        // gaps are 8pt each, not 10 — measured through NSHostingView, not assumed. So the
        // invisible hover chin was 243pt over a 239pt row on a 32pt notch. Deriving it
        // from the same spacing the HStack is given closes that gap; this test is here so
        // nobody "restores" the 20.
        let bothGaps = 2 * MusicLiveActivityMetrics.standardSpacing
        #expect(bothGaps == 16)
        #expect(metrics().addedWidth == 2 * metrics().artSize + bothGaps)
    }

    @Test("The artwork and the spectrum are always the same width")
    func keepsTheBlackRectangleOverTheHardware() {
        // This is the illusion. The black rectangle between them only sits over the
        // physical notch because the two slots either side of it match; if they ever
        // diverge the whole row slides and the cut-out lands on the wrong pixels.
        for height in stride(from: CGFloat(0), through: 60, by: 3) {
            for compact in [false, true] {
                let m = metrics(height: height, compact: compact)
                #expect(m.artSize == m.spectrumHeight)
            }
        }
    }

    @Test("Added width is the sum of its parts, never a separate guess")
    func addedWidthIsDerived() {
        for height in stride(from: CGFloat(0), through: 60, by: 3) {
            for compact in [false, true] {
                let m = metrics(height: height, compact: compact)
                #expect(m.addedWidth == m.artSize + m.spectrumHeight + 2 * m.spacing)
            }
        }
    }

    @Test("Compact narrows the row and never widens it")
    func compactOnlyShrinks() {
        for height in stride(from: CGFloat(0), through: 60, by: 3) {
            let standard = metrics(height: height, compact: false)
            let compact = metrics(height: height, compact: true)
            #expect(compact.artSize <= standard.artSize)
            #expect(compact.spacing <= standard.spacing)
            #expect(compact.addedWidth <= standard.addedWidth)
        }
    }

    @Test("Compact on a 32pt notch trades 16pt of width for smaller art")
    func compactSavesRealWidth() {
        let m = metrics(compact: true)
        #expect(m.artSize == 14)
        #expect(m.spacing == 6)
        #expect(m.addedWidth == 40)
    }

    @Test("Compact stops shrinking the artwork before it becomes mush")
    func compactFloorsTheArtwork() {
        // A 44pt notch compacts to 26; a 32pt one to the 14pt floor rather than to 14
        // and then below it on the next size down.
        #expect(metrics(height: 44, compact: true).artSize == 26)
        #expect(metrics(height: 30, compact: true).artSize == MusicLiveActivityMetrics.minimumArtSize)
        #expect(metrics(height: 26, compact: true).artSize >= MusicLiveActivityMetrics.minimumArtSize)
    }

    @Test("On a short notch compact degrades to standard rather than growing")
    func compactNeverExceedsStandard() {
        // Without the upper clamp the 14pt floor would make "compact" *wider* than
        // normal below a 26pt notch height, which reads as the setting being broken.
        let height: CGFloat = 22
        #expect(metrics(height: height, compact: false).artSize == 10)
        #expect(metrics(height: height, compact: true).artSize == 10)
    }

    @Test("A hidden notch produces no slots rather than negative ones")
    func fullscreenCollapses() {
        // effectiveClosedNotchHeight is 0 while the notch is hidden for a fullscreen app.
        for compact in [false, true] {
            let m = metrics(height: 0, compact: compact)
            #expect(m.artSize == 0)
            #expect(m.spectrumWidth == 0)
            #expect(m.spectrumHeight == 0)
        }
    }

    @Test("A pan stretches only the spectrum, and never past zero")
    func gestureStretchesTheSpectrum() {
        // Deliberate drag feedback that already existed: the row gives way in the
        // direction of the pan. It is transient, so it does not violate the symmetry
        // invariant above, which is measured at rest.
        let m = metrics(gesture: 10)
        #expect(m.spectrumWidth == 25)
        #expect(m.artSize == 20)

        // A pan the other way must not produce a negative frame.
        #expect(metrics(gesture: -500).spectrumWidth == 0)
    }
}
