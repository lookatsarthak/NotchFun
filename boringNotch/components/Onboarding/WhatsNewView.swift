//
//  WhatsNewView.swift
//  NotchFun
//

import AppKit
import Defaults
import SwiftUI

/// Shown once to people updating to 2.0, who never see setup again: what's new, and
/// switches for the new things worth trying that are off by default. New users get
/// the same ground in setup and never see it.
struct WhatsNewView: View {
    let onClose: () -> Void

    @Default(.showAccessoryBattery) private var airPods
    @Default(.enableLyrics) private var lyrics
    @Default(.persistentTrackInfo) private var trackBesideNotch
    private let claude = ClaudeCodeConnection.shared

    var body: some View {
        ZStack {
            OnboardingBackground()
            VStack(alignment: .leading, spacing: 18) {
                OnboardingStepHeader(
                    title: "What's new in NotchFun 2.0",
                    subtitle: "A quick look, and a few things to switch on if you like."
                )

                VStack(alignment: .leading, spacing: 10) {
                    highlight("sparkle", "The face shows what Claude Code is doing", "It twinkles while Claude works, looks up when it needs you, and smiles when it's done.")
                    highlight("airpods", "AirPods show each earbud and the case", "Left, right and case, with charging, when they connect.")
                    highlight("video", "Join calls from the notch", "A Join button on calendar calls, and a heads-up two minutes before.")
                    highlight("text.viewfinder", "Find screenshots by their words", "Clipboard search reads copied images on this Mac. Right-click for Copy Text.")
                    highlight("hand.draw", "Swipe on the music to skip", "And lyrics, an output menu and snippets. Settings are grouped by feature now.")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Try these")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    if ClaudeCodeConnection.claudeAppInstalled {
                        HStack {
                            switchLabel("Claude Code on the face", "Asks to open your .claude folder once.")
                            Spacer()
                            if claude.isConnected {
                                Text("Connected").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                            } else {
                                Button("Connect…") { claude.connect(from: NSApp.keyWindow) }
                                    .buttonStyle(OnboardingChipButtonStyle())
                            }
                        }
                    }
                    switchRow("AirPods battery", "Shown when they connect.", $airPods)
                    switchRow("Lyrics", "Looks up the song on lrclib.net.", $lyrics)
                    switchRow("Keep the track beside the notch", "Title and artist while music plays.", $trackBesideNotch)
                }

                Text("The shelf now shows the newest item first. You can change it in Settings → Shelf.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))

                HStack {
                    Spacer()
                    Button("Done", action: onClose)
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.dark)
    }

    private func highlight(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Label on the left, switch on the right edge, lined up with the Connect button.
    private func switchRow(_ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            switchLabel(title, detail)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.notchFunPurple)
        }
    }

    private func switchLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 13)).foregroundStyle(.white)
            Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// Shows What's New once, to people updating from 1.x.
@MainActor
enum WhatsNew {
    /// Bumped when a release has something to show updaters.
    static let version = 2
    private static var window: NSWindow?

    /// Called at launch when setup isn't showing. People who've never finished setup
    /// will see setup instead, which covers the same ground.
    static func showIfNeeded() {
        guard Defaults[.onboardingCompletedVersion] > 0, Defaults[.whatsNewShownVersion] < version else { return }
        Defaults[.whatsNewShownVersion] = version
        let hosting = NSHostingView(rootView: WhatsNewView(onClose: { close() }))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// New users finish setup instead; they never need this.
    static func markSeen() { Defaults[.whatsNewShownVersion] = version }

    static func close() {
        window?.close()
        window = nil
    }
}
