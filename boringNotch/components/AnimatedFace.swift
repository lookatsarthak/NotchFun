//
//  AnimatedFace.swift
//
// Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import SwiftUI

struct MinimalFaceFeatures: View {
    @State private var isBlinking = false
    @State var height:CGFloat = 20;
    @State var width:CGFloat = 30;
    
    var body: some View {
        VStack(spacing: 4) { // Adjusted spacing to fit within 30x30
            // Eyes
            HStack(spacing: 4) { // Adjusted spacing to fit within 30x30
                Eye(isBlinking: $isBlinking)
                Eye(isBlinking: $isBlinking)
            }
            
            // Nose and mouth combined
            VStack(spacing: 2) { // Adjusted spacing to fit within 30x30
                // Nose
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 3, height: 4)
                
                // Mouth (happy)
                GeometryReader { geometry in
                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        path.move(to: CGPoint(x: 0, y: height / 2))
                        path.addQuadCurve(to: CGPoint(x: width, y: height / 2), control: CGPoint(x: width / 2, y: height))
                    }
                    .stroke(Color.white, lineWidth: 2)
                }
                .frame(width: 14, height: 10)
            }
        }
        .frame(width: self.width, height: self.height) // Maximum size of face
        // `.task`, not `.onAppear` plus a Timer.
        //
        // The previous version scheduled a repeating Timer and never kept a reference to
        // it, so it could not be invalidated even in principle - and `.onAppear` runs
        // every time the face returns, which is on every music play/pause. Each stranded
        // timer went on calling `withAnimation` every three seconds forever, and unlike a
        // no-op that is a real SwiftUI transaction: it invalidates views and wakes the
        // render loop. The cost grew with uptime, which is exactly the shape of the
        // heat reports.
        //
        // SwiftUI cancels a `.task` when the view goes away, so this cannot leak however
        // many times the face appears.
        //
        // The blink is a cut, not an animation. The face shows whenever nothing is playing,
        // which is most of the day, and an animated blink redrew the notch at the display's
        // refresh rate for every close and open: measured, the face took NotchFun's idle CPU
        // from 10 ms a minute to 190-430. A real blink lasts about a tenth of a second, and
        // at four points tall an animated one looks no different. The gap varies, as real
        // blinking does, rather than ticking like a metronome.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 3500...6000)))
                guard !Task.isCancelled else { return }
                isBlinking = true
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                isBlinking = false
            }
        }
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
