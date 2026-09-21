//
//  MusicVisualizer.swift
//  NotchFun
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
import AppKit
import Cocoa
import SwiftUI

class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying: Bool = true
    private var isAnimating = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    private func setupBars() {
        let barWidth: CGFloat = 2
        let barCount = 4
        let spacing: CGFloat = barWidth
        let totalWidth = CGFloat(barCount) * (barWidth + spacing)
        let totalHeight: CGFloat = 14
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for i in 0 ..< barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.fillColor = NSColor.white.cgColor
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            let path = NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                                    xRadius: barWidth / 2,
                                    yRadius: barWidth / 2)
            barLayer.path = path.cgPath
            barLayers.append(barLayer)
            barScales.append(0.35)
            layer?.addSublayer(barLayer)
        }
    }
    
    /// One repeating keyframe animation per bar, handed to the render server once.
    ///
    /// This used to be a 0.3s `Timer` that added four `CABasicAnimation`s on every tick —
    /// so while music played, the main thread woke ~3.3 times a second and submitted 13
    /// animations a second, for the entire length of a track, with the notch closed.
    /// A repeating keyframe animation is submitted once and then owned entirely by the
    /// render server; the app does no per-frame work at all.
    ///
    /// Each bar gets its own duration and its own random keyframes so the four never
    /// march in step, which is what made the timer version look alive.
    private func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true

        for (i, barLayer) in barLayers.enumerated() {
            let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
            animation.values = [0.35] + (0..<9).map { _ in CGFloat.random(in: 0.35 ... 1.0) } + [0.35]
            animation.calculationMode = .cubic
            // Prime numbers either side of 3s, so the four bars drift apart instead of
            // re-synchronising on a common multiple.
            animation.duration = [2.9, 3.1, 3.7, 4.3][i % 4]
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            // Unchanged from the timer version: the bars are 2pt wide, so there is
            // nothing to gain from asking for more than 24fps.
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
            barLayer.add(animation, forKey: "scaleY")
        }
    }

    private func stopAnimating() {
        isAnimating = false
        resetBars()
    }

    deinit {
        // Nothing to invalidate any more. The previous version kept a Timer that the run
        // loop owned, so `[weak self]` let the view deallocate while the timer carried on
        // waking the main thread every 0.3s to call a method on nothing. There is no
        // timer now, and layer animations die with the layer.
    }

    private func resetBars() {
        for (i, barLayer) in barLayers.enumerated() {
            barLayer.removeAllAnimations()
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
            barScales[i] = 0.35
        }
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool
    
    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setPlaying(isPlaying)
        return spectrum
    }
    
    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
    }

    /// Stops the timer when SwiftUI removes the view.
    ///
    /// `deinit` covers this too, but only once the last reference goes. This runs at the
    /// moment the view leaves the hierarchy, which is the point the animation stops being
    /// worth anything - and the closed-notch ladder adds and removes this view on changes
    /// to play state, idle state, notch state, fullscreen and the sneak peek, so it
    /// happens often.
    static func dismantleNSView(_ nsView: AudioSpectrum, coordinator: ()) {
        nsView.setPlaying(false)
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
}
