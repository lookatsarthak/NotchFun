//
//  ClipboardIgnoredAppsSection.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI

/// The list of apps whose copies are never recorded.
///
/// The suggestions come from the history itself rather than a guessed list of "sensitive
/// apps": we already record which app each entry came from, so the apps offered are the
/// ones actually being copied out of. A password manager that marks its clips properly
/// barely appears there, which means the list naturally surfaces the apps we are *not*
/// already protecting the user from.
struct ClipboardIgnoredAppsSection: View {
    @Default(.clipboardIgnoredApps) private var ignored
    @ObservedObject private var clipboard = ClipboardStateViewModel.shared

    var body: some View {
        Section {
            if ignored.isEmpty {
                Text("Nothing excluded yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ignored, id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        icon(for: bundleID)
                        Text(displayName(for: bundleID))
                        Spacer(minLength: 0)
                        Button {
                            ignored.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Start saving copies from this app again")
                    }
                }
            }

            Menu("Add App…") {
                let suggestions = recentSourceApps
                if !suggestions.isEmpty {
                    Section("Apps you've copied from") {
                        ForEach(suggestions, id: \.self) { bundleID in
                            Button(displayName(for: bundleID)) { add(bundleID) }
                        }
                    }
                }
                Button("Choose…") { chooseApp() }
            }
        } header: {
            Text("Never save from these apps")
        } footer: {
            Text("Copies made in these apps are ignored completely — nothing is written to your history.")
        }
    }

    /// Apps that appear as the source of something in the history, most frequent first,
    /// excluding ones already on the list.
    private var recentSourceApps: [String] {
        clipboard.sourceAppFrequencies
            .filter { !ignored.contains($0) }
            .prefix(8)
            .map { $0 }
    }

    private func add(_ bundleID: String) {
        guard !ignored.contains(bundleID) else { return }
        ignored.append(bundleID)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        add(bundleID)
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            // The app may have been removed since it was excluded; the rule still stands.
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    @ViewBuilder
    private func icon(for bundleID: String) -> some View {
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
