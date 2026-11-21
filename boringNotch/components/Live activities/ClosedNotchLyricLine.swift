//
//  ClosedNotchLyricLine.swift
//  NotchFun
//

import SwiftUI

/// The current synced lyric line under the closed notch while music plays.
///
/// Redrawn when a new line starts and at no other time, through the same schedule the
/// open notch's lyrics use. A gap between lines (an instrumental) shows a note rather
/// than nothing, so the notch doesn't jump between one and two lines tall.
///
/// Lines change with a cut, not a fade. A cross-fade redrew the notch at the display's
/// refresh rate for a quarter second on every line, which measured about 1.3% CPU for as
/// long as the music played; a cut is one redraw.
struct ClosedNotchLyricLine: View {
    let width: CGFloat
    @Bindable private var musicManager = MusicManager.shared

    var body: some View {
        TimelineView(.explicit(musicManager.lyricRedrawDates())) { timeline in
            let line = musicManager.lyricLine(at: musicManager.elapsed(at: timeline.date))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Text(line.isEmpty ? "♪" : line)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: width)
        }
        .accessibilityLabel("Lyrics")
    }
}
