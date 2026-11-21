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
                    // Core Animation, not a SwiftUI animation: the compositor moves the
                    // text, so NotchFun does no work per frame. The SwiftUI version
                    // (ScrollingRow below) cost about 18% CPU while a long title scrolled.
                    LayerScrollingText(text: text, font: NSFont.preferredFont(forTextStyle: nsFont),
                                       color: NSColor(textColor), textWidth: textSize.width,
                                       startDelay: minDuration)
                        .frame(width: frameWidth, height: textSize.height * 1.3, alignment: .leading)
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


/// The text twice, scrolling left on a loop, animated by Core Animation.
///
/// One `CAAnimationGroup` repeats forever: a pause of `startDelay` with the start of the
/// text readable, then one scroll by exactly one copy's width, after which the second
/// copy sits where the first began and the loop restarts unseen. The animation lives in
/// the render server; NotchFun's own process does nothing until the text changes.
private struct LayerScrollingText: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor
    let textWidth: CGFloat
    let startDelay: Double

    func makeNSView(context: Context) -> MarqueeLayerView { MarqueeLayerView() }

    func updateNSView(_ view: MarqueeLayerView, context: Context) {
        view.configure(text: text, font: font, color: color, textWidth: textWidth, startDelay: startDelay)
    }
}

final class MarqueeLayerView: NSView {
    private let strip = CALayer()
    private let first = CATextLayer()
    private let second = CATextLayer()
    private var configuration = ""
    private var lineHeight: CGFloat = 0
    private static let gap: CGFloat = 20

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(strip)
        strip.addSublayer(first)
        strip.addSublayer(second)
        for textLayer in [first, second] {
            textLayer.truncationMode = .none
            textLayer.isWrapped = false
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    func configure(text: String, font: NSFont, color: NSColor, textWidth: CGFloat, startDelay: Double) {
        let key = "\(text)|\(textWidth)|\(color)|\(font.fontName)|\(font.pointSize)"
        guard key != configuration else { return }
        configuration = key

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        lineHeight = ceil(font.ascender - font.descender + font.leading)
        let width = ceil(textWidth) + 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, textLayer) in [first, second].enumerated() {
            textLayer.string = attributed
            textLayer.contentsScale = scale
            textLayer.frame = CGRect(x: CGFloat(index) * (ceil(textWidth) + Self.gap), y: 0, width: width, height: lineHeight)
        }
        strip.frame = CGRect(x: 0, y: (bounds.height - lineHeight) / 2, width: 2 * width + Self.gap, height: lineHeight)
        CATransaction.commit()

        strip.removeAllAnimations()
        let distance = ceil(textWidth) + Self.gap
        let scroll = CABasicAnimation(keyPath: "position.x")
        scroll.byValue = -distance
        scroll.beginTime = startDelay
        scroll.duration = Double((textWidth + 10) / 30)
        let loop = CAAnimationGroup()
        loop.animations = [scroll]
        loop.duration = startDelay + scroll.duration
        loop.repeatCount = .infinity
        loop.isRemovedOnCompletion = false
        strip.add(loop, forKey: "marquee")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.frame.origin.y = (bounds.height - lineHeight) / 2
        CATransaction.commit()
    }
}
