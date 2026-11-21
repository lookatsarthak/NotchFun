//
//  ClosedNotchLyricLine.swift
//  NotchFun
//

import SwiftUI

/// The current synced lyric line under the closed notch while music plays.
///
/// A Core Animation text layer whose text is swapped at each line start by one timer set
/// for the next line, and nothing else. The first version redrew through SwiftUI, and
/// every new line re-laid-out the closed notch: about 2% CPU for as long as the music
/// played. Swapping a layer's text is a single small commit. SwiftUI only passes in the
/// lyrics and the playback clock when they change.
///
/// A gap between lines (an instrumental) shows a note rather than nothing, so the notch
/// doesn't jump between one and two lines tall.
struct ClosedNotchLyricLine: View {
    let width: CGFloat
    @Bindable private var musicManager = MusicManager.shared

    var body: some View {
        LyricLineLayer(
            lines: musicManager.syncedLyrics,
            clock: .init(date: musicManager.timestampDate, elapsed: musicManager.elapsedTime,
                         rate: musicManager.isPlaying ? musicManager.playbackRate : 0),
            width: width
        )
        .frame(width: width, height: 18)
        .accessibilityLabel("Lyrics")
    }
}

/// Where playback is: `elapsed` seconds at `date`, moving at `rate`.
struct PlaybackClock: Equatable {
    let date: Date
    let elapsed: Double
    let rate: Double

    func elapsed(at now: Date) -> Double { elapsed + now.timeIntervalSince(date) * rate }
}

private struct LyricLineLayer: NSViewRepresentable {
    let lines: [LyricLine]
    let clock: PlaybackClock
    let width: CGFloat

    func makeNSView(context: Context) -> LyricLayerView { LyricLayerView() }

    func updateNSView(_ view: LyricLayerView, context: Context) {
        view.update(lines: lines, clock: clock)
    }

    static func dismantleNSView(_ view: LyricLayerView, coordinator: ()) {
        view.stop()
    }
}

final class LyricLayerView: NSView {
    private let textLayer = CATextLayer()
    private var lines: [LyricLine] = []
    private var clock = PlaybackClock(date: .distantPast, elapsed: 0, rate: 0)
    private var timer: Timer?
    private var shown: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        textLayer.alignmentMode = .center
        textLayer.truncationMode = .end
        textLayer.isWrapped = false
        layer?.addSublayer(textLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer.frame = bounds
        textLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    func update(lines: [LyricLine], clock: PlaybackClock) {
        guard lines != self.lines || clock != self.clock else { return }
        self.lines = lines
        self.clock = clock
        showCurrentLine()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Shows the line playing now, then sets the timer for the next line's start.
    private func showCurrentLine() {
        stop()
        let now = Date()
        let position = clock.elapsed(at: now)
        let text = Lyrics.lineIndex(at: position, in: lines)
            .map { lines[$0].text.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let line = text.isEmpty ? "♪" : text
        if line != shown {
            shown = line
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            textLayer.string = NSAttributedString(string: line, attributes: [
                .font: NSFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ])
            CATransaction.commit()
        }
        guard clock.rate > 0,
              let next = lines.first(where: { $0.time > position + 0.01 })
        else { return }
        let wait = (next.time - position) / clock.rate
        timer = Timer.scheduledTimer(withTimeInterval: max(0.05, wait), repeats: false) { [weak self] _ in
            self?.showCurrentLine()
        }
        timer?.tolerance = 0.05
    }
}
