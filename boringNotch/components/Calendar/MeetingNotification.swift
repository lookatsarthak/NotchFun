//
//  MeetingNotification.swift
//  NotchFun
//

import SwiftUI

/// The closed-notch heads-up before a call: the title on the left, when it starts on the
/// right. Opening the notch shows the event with its Join button.
///
/// The time is worked out once when the banner appears. A live relative date would
/// redraw every second for a banner that is gone in ten.
struct MeetingNotification: View {
    let event: EventModel
    let notchWidth: CGFloat

    private var startsIn: String {
        let minutes = Int((event.start.timeIntervalSinceNow / 60).rounded(.up))
        return minutes <= 0 ? "now" : "in \(minutes) min"
    }

    var body: some View {
        NotchBannerRow(notchWidth: notchWidth) {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.caption)
                    .foregroundStyle(Color(event.calendar.color))
                Text(event.title.isEmpty ? "Call" : event.title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 180, alignment: .trailing)
        } trailing: {
            Text(startsIn)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title) starts \(startsIn)")
    }
}
