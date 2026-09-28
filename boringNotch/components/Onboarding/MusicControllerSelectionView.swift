//
//  MusicControllerSelectionView.swift
//  NotchFun
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import Defaults


/// Shown when Now Playing has stopped working on this macOS, to pick an app to connect
/// to directly. Styled like setup, since it is the same kind of moment.
struct MusicControllerSelectionView: View {
    let onContinue: () -> Void

    @Default(.mediaController) var mediaController

    /// Starts on the current source only if it is still offered. It is shown precisely
    /// because the current source, Now Playing, no longer works - and is then left out
    /// of the list - so starting there left nothing selected, and Continue saved Now
    /// Playing all over again.
    @State private var selected: MediaControllerType = {
        let available = MediaControllerType.available
        return available.contains(Defaults[.mediaController])
            ? Defaults[.mediaController]
            : (available.first ?? Defaults[.mediaController])
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeader(
                title: "Choose a music source",
                subtitle: "Now Playing, which follows any app or browser, doesn't work on this version of macOS. Pick the app you listen with and the notch will connect to it directly. You can change this later in Settings."
            )

            VStack(spacing: 10) {
                ForEach(MediaControllerType.available) { controller in
                    ControllerOptionView(controller: controller, isSelected: selected == controller)
                        .onTapGesture { selected = controller }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Continue") {
                    mediaController = selected
                    NotificationCenter.default.post(name: .mediaControllerChanged, object: nil)
                    onContinue()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 44)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OnboardingBackground())
        .preferredColorScheme(.dark)
    }
}

struct ControllerOptionView: View {
    let controller: MediaControllerType
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.4))

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(controller.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.10 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(isSelected ? 0.28 : 0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(NotchMotion.control, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}


extension MediaControllerType {
    var description: String {
        switch self {
        case .nowPlaying:
            return "Works with most media apps, including browsers, to detect what's playing. Note: This may be removed in a future macOS version."
        case .spotify:
            return "Connects directly to the Spotify app."
        case .appleMusic:
            return "Connects directly to the Apple Music app."
        }
    }
}

#Preview {
    MusicControllerSelectionView(onContinue: {})
        .frame(width: 480, height: 440)
}
