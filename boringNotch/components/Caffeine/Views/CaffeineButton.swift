//
//  CaffeineButton.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// The caffeine toggle in the notch header.
///
/// Matches the 30×30 capsule shape of the mirror and settings buttons beside it. Plain
/// click toggles using the configured defaults; right-click opens the duration menu.
struct CaffeineButton: View {
    @ObservedObject private var caffeine = CaffeineManager.shared
    @Default(.caffeineMode) private var mode
    @Default(.caffeineDefaultDuration) private var defaultDuration

    @State private var haptics = false

    var body: some View {
        Button {
            toggle()
        } label: {
            Capsule()
                .fill(.black)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: caffeine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .foregroundStyle(caffeine.isActive ? Color.effectiveAccent : .white)
                        .imageScale(.medium)
                }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu { CaffeineDurationMenu() }
        .help(helpText)
        .sensoryFeedback(.alignment, trigger: haptics)
    }

    private var helpText: String {
        guard let session = caffeine.session else { return "Keep this Mac awake" }
        if let remaining = caffeine.remainingLabel {
            return "Caffeine on — \(remaining) left"
        }
        return "Caffeine on — \(session.duration.phrase)"
    }

    private func toggle() {
        caffeine.toggle(mode: mode, duration: defaultDuration)
        if Defaults[.enableHaptics] { haptics.toggle() }
    }
}

/// Duration picker, shared by the button's context menu and the menu-bar item.
struct CaffeineDurationMenu: View {
    @ObservedObject private var caffeine = CaffeineManager.shared
    @Default(.caffeineMode) private var mode

    var body: some View {
        if caffeine.isActive {
            Button("Turn Caffeine Off") { caffeine.deactivate() }
            Divider()
            Text("Change duration")
        }

        ForEach(Array(CaffeineDuration.presets.enumerated()), id: \.offset) { _, duration in
            Button(duration.title) {
                if caffeine.isActive {
                    caffeine.reschedule(to: duration)
                } else {
                    caffeine.activate(mode: mode, duration: duration)
                }
            }
        }

        Divider()
        CaffeineAppBoundMenu()
    }
}
