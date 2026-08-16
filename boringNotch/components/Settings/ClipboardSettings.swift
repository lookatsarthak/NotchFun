//
//  ClipboardSettings.swift
//  boringNotch
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct ClipboardSettings: View {
    @Default(.clipboardHistoryEnabled) var enabled
    @Default(.clipboardPasteOnSelect) var pasteOnSelect
    @Default(.clipboardHistorySize) var historySize
    @Default(.clipboardCheckInterval) var checkInterval

    @State private var showClearConfirmation = false
    @State private var accessibilityGranted: Bool?

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .clipboardHistoryEnabled) {
                    Text("Enable clipboard history")
                }
            } footer: {
                Text("Adds a Clipboard tab to the notch. While this is off, nothing is monitored, stored, or written to disk.")
            }

            Section {
                Stepper(value: $historySize, in: 10...999, step: 10) {
                    HStack {
                        Text("Entries to keep")
                        Spacer()
                        Text("\(historySize)").foregroundStyle(.secondary)
                    }
                }
                Defaults.Toggle(key: .clipboardIgnoreUniversalClipboard) {
                    Text("Ignore items copied from other devices")
                }
                Picker("Check for new copies", selection: $checkInterval) {
                    Text("Every 0.2s").tag(0.2)
                    Text("Every 0.5s").tag(0.5)
                    Text("Every 1s").tag(1.0)
                    Text("Every 2s").tag(2.0)
                }
            } header: {
                Text("History")
            } footer: {
                Text("Pinned entries are never counted against the limit or removed automatically.")
            }

            Section {
                Defaults.Toggle(key: .clipboardPasteOnSelect) {
                    Text("Paste into the active app on select")
                }
                Defaults.Toggle(key: .clipboardKeyboardNavigation) {
                    Text("Search and arrow-key navigation")
                }
            } header: {
                Text("Behaviour")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Both need Accessibility permission. Without it, selecting an entry still copies it — you just press ⌘V yourself.")
                    if accessibilityGranted == false {
                        HStack(spacing: 8) {
                            warningBadge("Accessibility permission not granted", "Needed for auto-paste and for typing to search.")
                            Button("Request Permission…") {
                                ClipboardAccessibility.prompt()
                            }
                            Button("Open Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                KeyboardShortcuts.Recorder("Open clipboard history:", name: .clipboardHistoryPanel)
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Opens the notch directly on the Clipboard tab.")
            }

            Section {
                Button("Clear History…", role: .destructive) {
                    showClearConfirmation = true
                }
                .confirmationDialog(
                    "Delete all clipboard history?",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete Everything", role: .destructive) {
                        ClipboardStateViewModel.shared.clearAll()
                    }
                    Button("Keep Pinned Items") {
                        ClipboardStateViewModel.shared.clearUnpinned()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } footer: {
                Text("Entries are stored on this Mac only, in Application Support, readable solely by your user account. Copies marked confidential by password managers are never recorded.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Clipboard")
        .onAppear {
            accessibilityGranted = ClipboardPasteService.isAuthorized
        }
    }
}
