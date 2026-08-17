//
//  CaffeineAppBoundMenu.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI

/// "Keep awake while ⟨app⟩ is running" — the Amphetamine-style trigger.
///
/// Lists currently running apps that have a UI. Uses `NSWorkspace`'s public API, so
/// there is no polling and no permission required; `CaffeineManager` ends the session
/// when it sees that app terminate.
struct CaffeineAppBoundMenu: View {
    @ObservedObject private var caffeine = CaffeineManager.shared
    @Default(.caffeineMode) private var mode

    var body: some View {
        Menu("While an app is running") {
            let apps = Self.candidateApps()
            if apps.isEmpty {
                Text("No other apps running")
            } else {
                ForEach(apps, id: \.bundleID) { app in
                    Button(app.name) {
                        caffeine.activate(
                            mode: mode,
                            duration: .whileAppRunning(bundleID: app.bundleID, name: app.name)
                        )
                    }
                }
            }
        }
    }

    struct Candidate: Hashable {
        let bundleID: String
        let name: String
    }

    /// Running apps worth offering: regular (Dock-visible) apps other than ourselves.
    /// Agents and daemons are excluded — binding a session to something the user cannot
    /// see or quit would be a session they can't end.
    static func candidateApps(
        from running: [NSRunningApplication] = NSWorkspace.shared.runningApplications,
        excluding ownBundleID: String? = Bundle.main.bundleIdentifier
    ) -> [Candidate] {
        var seen = Set<String>()
        return running
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> Candidate? in
                guard let bundleID = app.bundleIdentifier, bundleID != ownBundleID,
                      let name = app.localizedName, !name.isEmpty else { return nil }
                guard seen.insert(bundleID).inserted else { return nil }
                return Candidate(bundleID: bundleID, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
