//
//  MarqueeTextView.swift
//  NotchFun
//
//  Created by Richard Kunkli on 08/08/2024.
//

import SwiftUI

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        })
    }
}

struct MarqueeText: View {
    @Binding var text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat
    /// Scroll only while this is true. A scrolling marquee is a SwiftUI animation that
    /// redraws every display frame inside NotchFun: about 15% CPU for as long as the notch
    /// was open on a long title, playing or not. Paused, the title sits still and ends in
    /// an ellipsis.
    let isActive: Bool
    
    @State private var textSize: CGSize = .zero
    
    init(_ text: Binding<String>, font: Font = .body, nsFont: NSFont.TextStyle = .body, textColor: Color = .primary, backgroundColor: Color = .clear, minDuration: Double = 3.0, frameWidth: CGFloat = 200, isActive: Bool = true) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
        self.isActive = isActive
    }
    
    private var needsScrolling: Bool {
        textSize.width > frameWidth
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                if needsScrolling && isActive {
                    // Its own view, keyed by the text and width, so that a new title or a
                    // pause removes it from the tree. A repeating SwiftUI animation can't be
                    // stopped by changing its value; it ends only when its view goes away.
                    ScrollingRow(text: text, font: font, textColor: textColor, backgroundColor: backgroundColor,
                                 textWidth: textSize.width, startDelay: minDuration)
                        .id("\(text)|\(textSize.width)")
                } else {
                    Text(text)
                        .font(font)
                        .foregroundColor(textColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: frameWidth, alignment: .leading)
                        .background(backgroundColor)
                }
            }
            // Measured apart from whichever row is showing.
            .background(alignment: .leading) {
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                        textSize = CGSize(width: width, height: NSFont.preferredFont(forTextStyle: nsFont).pointSize)
                    }
            }
            .frame(width: frameWidth, alignment: .leading)
            .clipped()
        }
        .frame(height: textSize.height * 1.3)
    }
}

/// The text twice, scrolling left forever: when the first copy has gone, the second is
/// where the first started, and the loop restarts unseen.
private struct ScrollingRow: View {
    let text: String
    let font: Font
    let textColor: Color
    let backgroundColor: Color
    let textWidth: CGFloat
    let startDelay: Double

    @State private var animate = false

    var body: some View {
        HStack(spacing: 20) {
            Text(text)
            Text(text)
        }
        .font(font)
        .foregroundColor(textColor)
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: animate ? -(textWidth + 20) : 0)
        .animation(
            animate
                ? .linear(duration: Double((textWidth + 10) / 30)).delay(startDelay).repeatForever(autoreverses: false)
                : .none,
            value: animate
        )
        .background(backgroundColor)
        .onAppear { animate = true }
    }
}
