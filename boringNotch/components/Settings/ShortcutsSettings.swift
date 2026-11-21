//
//  ShortcutsSettings.swift
//  NotchFun
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                Text(
                    "Sneak Peek shows the media title and artist under the notch for a few seconds."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            }
            Section {
                KeyboardShortcuts.Recorder("Keyboard backlight down:", name: .decreaseBacklight)
                KeyboardShortcuts.Recorder("Keyboard backlight up:", name: .increaseBacklight)
            } header: {
                Text("Keyboard backlight")
            } footer: {
                Text(
                    "Unset by default — ⌘F1 and ⌘F2 already toggle display mirroring on most Macs, so NotchFun will not take them without being asked."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                Defaults.Toggle(key: .allowNotchMessages) {
                    Text("Show messages from Shortcuts and links")
                }
            } header: {
                Text("Messages")
            } footer: {
                Text(
                    "The Show in Notch action, or a link like notchfun://show?text=Build%20passed&icon=checkmark.circle, shows a line in the closed notch for a few seconds. Text only: a message can't open anything, and more than five in ten seconds are dropped."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shortcuts")
    }
}
