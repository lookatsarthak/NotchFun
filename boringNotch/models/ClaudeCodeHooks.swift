//
//  ClaudeCodeHooks.swift
//  NotchFun
//

import Foundation

/// The hooks NotchFun adds to Claude Code's `settings.json`, and how they're added and
/// taken out again.
///
/// Each hook tells NotchFun what a session is doing by opening a link in the background:
/// `notchfun://agent?state=working&session=<id>`. The session id comes from the JSON
/// Claude Code passes every hook on stdin.
///
/// Every hook:
/// - runs **async**, so Claude Code never waits on it;
/// - does nothing unless NotchFun is running, so quitting NotchFun isn't undone by the
///   next tool call relaunching it;
/// - always exits 0, so Claude Code never shows a hook error because of NotchFun.
///
/// NotchFun's entries are recognised by the `notchfun://agent` in their command, so
/// connecting twice doesn't duplicate them and disconnecting removes exactly them, never
/// anything else in the file.
enum ClaudeCodeHooks {
    /// What a hook reports.
    enum Report: String, Sendable {
        case working, waiting, done, error, end
    }

    /// One hook to add: the event, an optional matcher, and what it reports.
    struct Entry: Equatable, Sendable {
        let event: String
        let matcher: String?
        let report: Report
    }

    static let marker = "notchfun://agent"

    /// Which Claude Code events map to which face state.
    static let entries: [Entry] = [
        Entry(event: "UserPromptSubmit", matcher: nil, report: .working),
        Entry(event: "PreToolUse", matcher: nil, report: .working),
        Entry(event: "PostToolUse", matcher: nil, report: .working),
        Entry(event: "Notification", matcher: "permission_prompt", report: .waiting),
        Entry(event: "Notification", matcher: "elicitation_dialog", report: .waiting),
        Entry(event: "Stop", matcher: nil, report: .done),
        Entry(event: "StopFailure", matcher: nil, report: .error),
        Entry(event: "SessionEnd", matcher: nil, report: .end),
    ]

    /// The shell command for one report. Claude Code runs it with bash and the event's
    /// JSON on stdin. The first `"session_id": "…"` in it is Claude Code's own field (the
    /// common fields come first, and one inside a tool's input would be escaped), and a
    /// session id is a UUID, so it goes into the link as is.
    static func command(for report: Report, processName: String = "NotchFun") -> String {
        let session = #"$(/usr/bin/grep -o '"session_id" *: *"[^"]*"' | /usr/bin/head -n 1 | /usr/bin/sed 's/.*"\([^"]*\)"$/\1/')"#
        return "/usr/bin/pgrep -qx \(processName) && /usr/bin/open -g \"\(marker)?state=\(report.rawValue)&session=\(session)\"; exit 0"
    }

    // MARK: - Editing settings.json

    /// True if the settings already hold NotchFun's hooks.
    static func isConnected(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in
            (groups as? [[String: Any]])?.contains(where: groupIsOurs) ?? false
        }
    }

    /// The settings with NotchFun's hooks, replacing any older copy of them and leaving
    /// everything else exactly as it was.
    static func connected(_ settings: [String: Any], processName: String = "NotchFun") -> [String: Any] {
        var settings = disconnected(settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for entry in entries {
            var group: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": command(for: entry.report, processName: processName),
                    "async": true,
                    "timeout": 5,
                ]],
            ]
            if let matcher = entry.matcher { group["matcher"] = matcher }
            var groups = hooks[entry.event] as? [[String: Any]] ?? []
            groups.append(group)
            hooks[entry.event] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    /// The settings without NotchFun's hooks. Events left with no hooks are removed, and
    /// so is an emptied "hooks" key; anything else is untouched.
    static func disconnected(_ settings: [String: Any]) -> [String: Any] {
        guard let hooks = settings["hooks"] as? [String: Any] else { return settings }
        var settings = settings
        var kept: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                kept[event] = value // not a shape we know; leave it alone
                continue
            }
            let remaining = groups.filter { !groupIsOurs($0) }
            if !remaining.isEmpty { kept[event] = remaining }
        }
        if kept.isEmpty { settings["hooks"] = nil } else { settings["hooks"] = kept }
        return settings
    }

    /// A matcher group whose every handler is one of ours. A group someone else also put
    /// handlers in is never removed whole.
    private static func groupIsOurs(_ group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]], !handlers.isEmpty else { return false }
        return handlers.allSatisfy { ($0["command"] as? String)?.contains(marker) == true }
    }
}
