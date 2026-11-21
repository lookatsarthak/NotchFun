//
//  AnimatedFace.swift
//
// Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import SwiftUI

/// The face beside the notch. Idle it's white and blinks. While a Claude Code session is
/// active it changes, without any words:
///
/// - **Working:** Claude's warm orange, with eyes that become small turning sparkles.
/// - **Needs you:** wide eyes, a small "o", and a nudge every few seconds until you answer.
/// - **Done:** green, happy closed eyes and a big smile, with one pulse, for a moment.
/// - **Error:** red, × eyes and a frown.
///
/// Every change is a cut, like the blink, not a continuous animation: a long working
/// session costs one redraw per sparkle step, not one per display frame.
struct MinimalFaceFeatures: View {
    @State private var isBlinking = false
    @State var height:CGFloat = 20;
    @State var width:CGFloat = 30;

    private let agent = AgentStatusCenter.shared
    @State private var sparkleTurned = false
    @State private var pulse = false

    private var state: AgentBoard.State? { agent.shown }

    static let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let doneGreen = Color(red: 0.40, green: 0.86, blue: 0.48)
    static let errorRed = Color(red: 1.0, green: 0.42, blue: 0.40)

    private var tint: Color {
        switch state {
        case .working, .waiting: return Self.claudeOrange
        case .done: return Self.doneGreen
        case .error: return Self.errorRed
        case nil: return .white
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                eye
                eye
            }
            .frame(height: 6)

            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 3, height: 4)
                mouth
                    .frame(width: 14, height: 10)
            }
        }
        .frame(width: self.width, height: self.height)
        .scaleEffect(pulse ? 1.2 : 1)
        // The blink. `.task`, so it ends with the view, and a cut rather than an
        // animation: the face is up most of the day and an animated blink redrew the
        // notch at the display's refresh rate. It skips while the display sleeps.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 3500...6000)))
                guard !Task.isCancelled else { return }
                guard CGDisplayIsAsleep(CGMainDisplayID()) == 0, state == nil || state == .working else { continue }
                isBlinking = true
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                isBlinking = false
            }
        }
        // Claude Code's states, restarted when the state changes and gone with the view.
        .task(id: state) {
            switch state {
            case .working:
                while !Task.isCancelled {
                    if CGDisplayIsAsleep(CGMainDisplayID()) == 0 { sparkleTurned.toggle() }
                    try? await Task.sleep(for: .milliseconds(600))
                }
            case .waiting:
                // A nudge on arrival, every 3 s for the first half minute, then every
                // 15 s until you answer: the one state that keeps asking. A session can
                // wait an hour while you're away, and a nudge every 3 s was 1.3% CPU for
                // all of it; the wide eyes say "waiting" between nudges anyway.
                let start = Date()
                while !Task.isCancelled {
                    if CGDisplayIsAsleep(CGMainDisplayID()) == 0 {
                        withAnimation(NotchMotion.sneak) { pulse = true }
                        try? await Task.sleep(for: .milliseconds(280))
                        withAnimation(NotchMotion.sneak) { pulse = false }
                    }
                    try? await Task.sleep(for: .seconds(Date().timeIntervalSince(start) < 30 ? 3 : 15))
                }
            case .done:
                // One pulse on arrival, then stillness.
                withAnimation(NotchMotion.sneak) { pulse = true }
                try? await Task.sleep(for: .milliseconds(280))
                withAnimation(NotchMotion.sneak) { pulse = false }
            case .error, nil:
                break
            }
        }
    }

    @ViewBuilder
    private var eye: some View {
        switch state {
        case .working:
            // A twinkle: the sparkle steps between full and small. Turning it instead made
            // it look like the error face's × eyes.
            SparkleShape()
                .fill(tint)
                .frame(width: 6, height: 6)
                .scaleEffect(sparkleTurned ? 0.6 : 1)
        case .waiting:
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
        case .done:
            // ^ : a happy closed eye.
            Path { path in
                path.move(to: CGPoint(x: 0, y: 4))
                path.addLine(to: CGPoint(x: 3, y: 1))
                path.addLine(to: CGPoint(x: 6, y: 4))
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .frame(width: 6, height: 5)
        case .error:
            Path { path in
                path.move(to: CGPoint(x: 0.5, y: 0.5)); path.addLine(to: CGPoint(x: 4.5, y: 4.5))
                path.move(to: CGPoint(x: 4.5, y: 0.5)); path.addLine(to: CGPoint(x: 0.5, y: 4.5))
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 5, height: 5)
        case nil:
            Eye(isBlinking: $isBlinking)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        if state == .waiting {
            Circle()
                .stroke(tint, lineWidth: 1.6)
                .frame(width: 5, height: 5)
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            let bend: CGFloat = switch state {
            case .done: 1.35
            case .error: 0
            default: 1
            }
            GeometryReader { geometry in
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    path.move(to: CGPoint(x: 0, y: height / 2))
                    path.addQuadCurve(to: CGPoint(x: width, y: height / 2), control: CGPoint(x: width / 2, y: height * bend))
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }
}

/// A four-pointed sparkle, drawn here rather than taken from a logo.
private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let inner = r * 0.32
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let radius = i.isMultiple(of: 2) ? r : inner
            let point = CGPoint(x: c.x + CGFloat(cos(angle)) * radius, y: c.y + CGFloat(sin(angle)) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct Eye: View {
    @Binding var isBlinking: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white)
            .frame(width: 4, height: isBlinking ? 1 : 4)
            .frame(maxWidth: 15, maxHeight: 15) // Adjusted max size
    }
}

#if DEBUG
struct MinimalFaceFeatures_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            MinimalFaceFeatures()
        }
        .previewLayout(.fixed(width: 60, height: 60)) // Adjusted preview size for better visibility
    }
}
#endif
