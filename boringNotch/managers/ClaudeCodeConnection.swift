//
//  ClaudeCodeConnection.swift
//  NotchFun
//

import AppKit
import Defaults
import Foundation

/// Connects Claude Code to the face by adding NotchFun's hooks to `~/.claude/settings.json`,
/// with no Terminal involved.
///
/// NotchFun is sandboxed and can't open that folder by itself. "Connect" shows the macOS
/// folder dialog already inside `~/.claude`, and choosing it there is what gives NotchFun
/// access to that one folder. A security-scoped bookmark keeps the access, so Disconnect
/// works later without asking again. Only `settings.json` in it is ever read or written,
/// and the original is copied to `settings.json.notchfun-backup` before the first change.
///
/// Claude Code watches its settings file, so open sessions pick the hooks up straight away.
@MainActor
@Observable
final class ClaudeCodeConnection {
    static let shared = ClaudeCodeConnection()

    private(set) var isConnected = false
    /// Why the last attempt didn't work, for Settings to show.
    private(set) var problem: String?

    private let onlyClaudeFolder = OnlyClaudeFolder()

    private final class OnlyClaudeFolder: NSObject, NSOpenSavePanelDelegate {
        func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
            url.lastPathComponent == ".claude"
        }
    }

    private init() {
        isConnected = Defaults[.claudeCodeFolderBookmark] != nil && readConnected() == true
    }

    /// The real home folder, not the app's container.
    private static var homeFolder: URL {
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Connect and disconnect

    func connect() {
        problem = nil
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = Self.homeFolder.appendingPathComponent(".claude", isDirectory: true)
        panel.prompt = "Connect"
        // Everything inside .claude is greyed out, so Connect can only choose .claude
        // itself, never a subfolder clicked by mistake.
        panel.delegate = onlyClaudeFolder
        panel.message = "NotchFun adds a few hooks to settings.json in this folder, so the face can show what Claude Code is doing. Nothing else here is read or changed."
        // A sheet on the Settings window, where Connect was clicked. A free-standing dialog
        // runs in a system process that doesn't follow NotchFun onto a full-screen app's
        // desktop: over a full-screen app it opened on the regular desktop, out of sight,
        // and the click seemed to do nothing. A sheet always shows on its window.
        NSApp.activate(ignoringOtherApps: true)
        if let settings = SettingsWindowController.shared.window, settings.isVisible {
            panel.beginSheetModal(for: settings) { [weak self] response in
                guard response == .OK, let folder = panel.url else { return }
                MainActor.assumeIsolated { self?.connect(folder: folder) }
            }
        } else {
            guard panel.runModal() == .OK, let folder = panel.url else { return }
            connect(folder: folder)
        }
    }

    func disconnect() {
        problem = nil
        guard let folder = resolveFolder() else {
            // The bookmark no longer resolves (the folder moved or was deleted): nothing to
            // remove, so just forget it.
            Defaults[.claudeCodeFolderBookmark] = nil
            isConnected = false
            return
        }
        defer { folder.stopAccessingSecurityScopedResource() }
        do {
            try edit(in: folder) { ClaudeCodeHooks.disconnected($0) }
            Defaults[.claudeCodeFolderBookmark] = nil
            isConnected = false
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Writes the hooks into the chosen folder. Separate from the dialog so tests can call it.
    func connect(folder: URL) {
        guard folder.lastPathComponent == ".claude" else {
            problem = "Choose the .claude folder in your home folder. If it isn't there, open Claude Code once first."
            return
        }
        do {
            let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            try edit(in: folder) { ClaudeCodeHooks.connected($0) }
            Defaults[.claudeCodeFolderBookmark] = bookmark
            isConnected = true
        } catch {
            problem = error.localizedDescription
        }
    }

    // MARK: - The file

    private enum EditError: LocalizedError {
        case notJSON
        var errorDescription: String? {
            "Claude Code's settings.json isn't valid JSON, so NotchFun left it alone. Fix it in Claude Code, then connect again."
        }
    }

    /// Reads settings.json (or starts from nothing), applies `change`, keeps a one-time
    /// backup of the original, and writes the result atomically.
    private func edit(in folder: URL, _ change: ([String: Any]) -> [String: Any]) throws {
        let file = folder.appendingPathComponent("settings.json")
        let backup = folder.appendingPathComponent("settings.json.notchfun-backup")
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: file), !data.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw EditError.notJSON
            }
            settings = object
            if !FileManager.default.fileExists(atPath: backup.path) {
                try data.write(to: backup, options: .atomic)
            }
        }
        let updated = change(settings)
        let data = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: file, options: .atomic)
    }

    private func resolveFolder() -> URL? {
        guard let bookmark = Defaults[.claudeCodeFolderBookmark] else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource()
        else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            Defaults[.claudeCodeFolderBookmark] = fresh
        }
        return url
    }

    /// Whether the hooks are still in the file. Someone may have removed them by hand.
    private func readConnected() -> Bool? {
        guard let folder = resolveFolder() else { return nil }
        defer { folder.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("settings.json")),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return ClaudeCodeHooks.isConnected(settings)
    }
}
