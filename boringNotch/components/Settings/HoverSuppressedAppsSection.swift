//
//  HoverSuppressedAppsSection.swift
//  NotchFun
//

import AppKit
import Defaults
import SwiftUI

/// Apps in which hovering the notch doesn't open it: games, video editors, anything
/// where the pointer lives near the top of the screen. Clicking the notch, the keyboard
/// shortcut and Shortcuts still open it.
struct HoverSuppressedAppsSection: View {
    @Default(.hoverSuppressedApps) private var apps

    var body: some View {
        Section {
            if apps.isEmpty {
                Text("None yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(apps, id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        AppListIcon(bundleID: bundleID)
                        Text(AppListIcon.displayName(for: bundleID))
                        Spacer(minLength: 0)
                        Button {
                            apps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open on hover in this app again")
                    }
                }
            }

            Menu("Add App…") {
                let running = runningApps
                if !running.isEmpty {
                    Section("Open now") {
                        ForEach(running, id: \.self) { bundleID in
                            Button(AppListIcon.displayName(for: bundleID)) { add(bundleID) }
                        }
                    }
                }
                Button("Choose…") { chooseApp() }
            }
        } header: {
            Text("Don't open on hover in these apps")
        } footer: {
            Text("While one of these is the active app, hovering the notch does nothing. Clicking it and the keyboard shortcut still work.")
        }
    }

    /// Regular apps running now, by name, minus NotchFun and ones already listed.
    private var runningApps: [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { $0 != Bundle.main.bundleIdentifier && !apps.contains($0) }
            .sorted { AppListIcon.displayName(for: $0).localizedCaseInsensitiveCompare(AppListIcon.displayName(for: $1)) == .orderedAscending }
    }

    private func add(_ bundleID: String) {
        guard !apps.contains(bundleID) else { return }
        apps.append(bundleID)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        add(bundleID)
    }
}

/// An app's icon and name from its bundle ID, for app lists in Settings.
struct AppListIcon: View {
    let bundleID: String

    static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "questionmark.app")
                .foregroundStyle(.secondary)
        }
    }
}
