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
    @Default(.clipboardAutoClearDelay) var autoClearDelay

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
                Text("Pinned entries are never counted against the limit or removed automatically. While history is on, NotchFun checks the clipboard at the interval above.")
            }

            Section {
                Defaults.Toggle(key: .clipboardSkipSensitiveText) {
                    Text("Skip text that looks like a password")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Copies marked as passwords by the app that made them are always skipped. This adds a guess for apps that don't mark them, like a token copied from a terminal. Being a guess, it can miss some and skip text that only mentions a password.")
            }

            ClipboardIgnoredAppsSection()

            Section {
                Picker("Empty it after copying", selection: $autoClearDelay) {
                    Text("Never").tag(0.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                }
                Defaults.Toggle(key: .clipboardClearOnSleep) {
                    Text("When the Mac sleeps")
                }
                Defaults.Toggle(key: .clipboardClearOnDisplaySleep) {
                    Text("When the display sleeps")
                }
                Defaults.Toggle(key: .clipboardClearOnLock) {
                    Text("When the screen locks")
                }
            } header: {
                Text("Clear the system clipboard")
            } footer: {
                Text("This empties the clipboard itself, so ⌘V will paste nothing. Your saved history is not affected.")
            }

            Section {
                Defaults.Toggle(key: .clipboardCleanLinks) {
                    Text("Remove tracking parameters from links")
                }
            } header: {
                Text("Links")
            } footer: {
                Text("Strips utm_, fbclid, gclid and similar from a copied link when you paste it — never from a parameter that selects content, like a YouTube timestamp. Only applies to a copy that is a single link, and pastes it as plain text. Your history keeps the original.")
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
                KeyboardShortcuts.Recorder("Paste as plain text:", name: .pasteAsPlainText)
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
