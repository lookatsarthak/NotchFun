//
//  LottieAnimationContainer.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 29..
//

import SwiftUI
import Defaults

struct LottieAnimationContainer: View {
    @Default(.selectedVisualizer) var selectedVisualizer
    @ObservedObject private var musicManager = MusicManager.shared

    var body: some View {
        if let selectedVisualizer {
            LottieView(url: selectedVisualizer.url, speed: selectedVisualizer.speed, loopMode: .loop)
        } else {
            // The app's own spectrum, not a Lottie fetched from a third-party CDN.
            //
            // The default used to be a hardcoded lottiefiles.com URL, downloaded every
            // time this view appeared. That put a network round-trip and an outside host
            // in the path of an app that otherwise works entirely offline, and when it
            // failed - no network, asset moved - the callback simply handed back nil and
            // the view rendered nothing, with no way to tell that from "no music".
            //
            AudioSpectrumView(isPlaying: .init(
                get: { musicManager.isPlaying },
                set: { _ in }
            ))
        }
    }
}

#Preview {
    LottieAnimationContainer()
}
