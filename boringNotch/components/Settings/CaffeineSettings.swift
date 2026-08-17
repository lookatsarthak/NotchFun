//
//  CaffeineSettings.swift
//  boringNotch
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct CaffeineSettings: View {
    @ObservedObject private var caffeine = CaffeineManager.shared
    @Default(.caffeineMode) private var mode
    @Default(.caffeineDefaultDuration) private var defaultDuration

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    if let session = caffeine.session {
                        Text(caffeine.remainingLabel.map { "On — \($0) left" }
                             ?? "On — \(session.duration.title.lowercased())")
                            .foregroundStyle(Color.effectiveAccent)
                    } else {
                        Text("Off").foregroundStyle(.secondary)
                    }
                }
                Button(caffeine.isActive ? "Turn Off" : "Turn On") {
                    caffeine.toggle(mode: mode, duration: defaultDuration)
                }
            } header: {
                Text("Caffeine")
            } footer: {
                Text("Stops the Mac going to sleep on its own. Needs no permissions.")
            }

            Section {
                Picker("Keep awake", selection: $mode) {
                    ForEach(CaffeineMode.allCases, id: \.self) { m in
                        Text(m.title).tag(m)
                    }
                }
                Picker("Default duration", selection: $defaultDuration) {
                    ForEach(Array(CaffeineDuration.presets.enumerated()), id: \.offset) { _, d in
                        Text(d.title).tag(d)
                    }
                }
            } header: {
                Text("Behaviour")
            } footer: {
                Text("\(mode.detail) The default duration is what a plain click on the notch button uses; right-click it to pick a different one, or to keep the Mac awake only while a chosen app is running.")
            }

            Section {
                Defaults.Toggle(key: .caffeineButtonInNotch) {
                    Text("Show button in the notch")
                }
                Defaults.Toggle(key: .caffeineShowNotification) {
                    Text("Show an indicator when it turns on or off")
                }
                Defaults.Toggle(key: .caffeineActivateOnLaunch) {
                    Text("Turn on when NotchFun launches")
                }
            } header: {
                Text("Appearance")
            }

            Section {
                KeyboardShortcuts.Recorder("Toggle caffeine:", name: .toggleCaffeine)
            } header: {
                Text("Shortcut")
            } footer: {
                Text("No shortcut is set by default, to avoid taking one another app already uses.")
            }

            Section {} footer: {
                Text("Caffeine cannot keep a MacBook awake with the lid closed — macOS only allows that with administrator privileges, which NotchFun does not ask for. Use an external display and power adapter for clamshell use.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Caffeine")
    }
}
