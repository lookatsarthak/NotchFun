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
                             ?? "On — \(session.duration.phrase)")
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
                Text("Stops the Mac going to sleep on its own. Needs no permissions. While it is on your Mac will not idle-sleep, so expect the battery to drain faster.")
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
                Defaults.Toggle(key: .caffeineIndicatorInNotch) {
                    Text("Show a cup in the notch while active")
                }
                Defaults.Toggle(key: .caffeineActivateOnLaunch) {
                    Text("Turn on when NotchFun launches")
                }
                Defaults.Toggle(key: .caffeineOnPowerConnected) {
                    Text("Turn on when connected to power")
                }
                Defaults.Toggle(key: .caffeineOnExternalDisplay) {
                    Text("Turn on when an external display is connected")
                }
            } header: {
                Text("Appearance and automation")
            } footer: {
                Text("A session started automatically also ends automatically when you unplug or disconnect. One you started yourself is left alone. The cup appears in the closed notch and steps aside for volume, brightness and battery indicators, returning when they disappear.")
            }

            Section {
                KeyboardShortcuts.Recorder("Toggle caffeine:", name: .toggleCaffeine)
            } header: {
                Text("Shortcut")
            } footer: {
                Text("No shortcut is set by default, to avoid taking one another app already uses.")
            }

            Section {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "laptopcomputer.slash")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Closing the lid still sleeps the Mac")
                        Text("Caffeine cannot prevent this. macOS only allows overriding lid sleep with administrator privileges, which NotchFun does not ask for. For clamshell use, connect an external display and power adapter.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "battery.25")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("A critically low battery wins")
                        Text("macOS may sleep the Mac to protect against data loss regardless of caffeine.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("What caffeine cannot do")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Caffeine")
    }
}
