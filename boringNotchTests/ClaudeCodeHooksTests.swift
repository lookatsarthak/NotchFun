//
//  ClaudeCodeHooksTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Connecting Claude Code")
struct ClaudeCodeHooksTests {

    /// Settings someone already has: a model choice, permissions, and a hook of their own.
    private var existing: [String: Any] {
        [
            "model": "opus",
            "permissions": ["allow": ["Bash(git status)"]],
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "say done"]]]],
            ],
        ]
    }

    private func hooks(_ settings: [String: Any]) -> [String: [[String: Any]]] {
        (settings["hooks"] as? [String: Any] ?? [:]).compactMapValues { $0 as? [[String: Any]] }
    }

    private func commands(_ settings: [String: Any], _ event: String) -> [String] {
        (hooks(settings)[event] ?? []).flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    @Test("Connecting adds every hook and keeps everything else")
    func connect() {
        let result = ClaudeCodeHooks.connected(existing)
        #expect(ClaudeCodeHooks.isConnected(result))
        #expect(result["model"] as? String == "opus")
        #expect((result["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(git status)"])
        #expect(commands(result, "Stop").contains("say done"))
        for entry in ClaudeCodeHooks.entries {
            #expect(commands(result, entry.event).contains(ClaudeCodeHooks.command(for: entry.report)))
        }
        let notification = hooks(result)["Notification"] ?? []
        #expect(Set(notification.compactMap { $0["matcher"] as? String }) == ["permission_prompt", "elicitation_dialog"])
    }

    @Test("Every hook is async with a short timeout")
    func asyncHooks() {
        let result = ClaudeCodeHooks.connected([:])
        for groups in hooks(result).values {
            for group in groups {
                for handler in group["hooks"] as? [[String: Any]] ?? [] {
                    #expect(handler["async"] as? Bool == true)
                    #expect(handler["timeout"] as? Int == 5)
                    #expect(handler["type"] as? String == "command")
                }
            }
        }
    }

    @Test("Connecting twice doesn't duplicate anything")
    func idempotent() {
        let once = ClaudeCodeHooks.connected(existing)
        let twice = ClaudeCodeHooks.connected(once)
        #expect(commands(twice, "Stop").count == 2)
        #expect(commands(twice, "PreToolUse").count == 1)
        #expect(NSDictionary(dictionary: once) == NSDictionary(dictionary: twice))
    }

    @Test("Disconnecting restores the original settings exactly")
    func disconnect() {
        let result = ClaudeCodeHooks.disconnected(ClaudeCodeHooks.connected(existing))
        #expect(!ClaudeCodeHooks.isConnected(result))
        #expect(NSDictionary(dictionary: result) == NSDictionary(dictionary: existing))
    }

    @Test("Disconnecting settings that had no hooks removes the hooks key")
    func disconnectFromEmpty() {
        let result = ClaudeCodeHooks.disconnected(ClaudeCodeHooks.connected(["model": "opus"]))
        #expect(result["hooks"] == nil)
        #expect(result["model"] as? String == "opus")
    }

    @Test("A group someone else added to is never removed")
    func sharedGroup() {
        let mixed: [String: Any] = ["hooks": ["Stop": [["hooks": [
            ["type": "command", "command": ClaudeCodeHooks.command(for: .done)],
            ["type": "command", "command": "say done"],
        ]]]]]
        #expect(commands(ClaudeCodeHooks.disconnected(mixed), "Stop").count == 2)
    }

    @Test("Unknown shapes under hooks are left alone")
    func unknownShapes() {
        let odd: [String: Any] = ["hooks": ["Custom": "something"]]
        let result = ClaudeCodeHooks.disconnected(ClaudeCodeHooks.connected(odd))
        #expect((result["hooks"] as? [String: Any])?["Custom"] as? String == "something")
    }

    @Test("The hook stays quiet when NotchFun isn't running, and always exits 0")
    func command() {
        let command = ClaudeCodeHooks.command(for: .waiting)
        #expect(command.hasPrefix("/usr/bin/pgrep -qx NotchFun && /usr/bin/open -g "))
        #expect(command.hasSuffix("; exit 0"))
        #expect(command.contains("notchfun://agent?state=waiting&session="))
    }

    // MARK: Links

    @Test("Agent links parse, and odd sessions collapse to one")
    func agentLinks() {
        #expect(NotchURLCommand(url: URL(string: "notchfun://agent?state=working&session=4f1c-aa")!) == .agent(.working, session: "4f1c-aa"))
        #expect(NotchURLCommand(url: URL(string: "notchfun://agent?state=DONE&session=x")!) == .agent(.done, session: "x"))
        #expect(NotchURLCommand(url: URL(string: "notchfun://agent?state=working&session=")!) == .agent(.working, session: "unknown"))
        #expect(NotchURLCommand(url: URL(string: "notchfun://agent?state=working&session=a%20b%3Cscript%3E")!) == .agent(.working, session: "unknown"))
        #expect(NotchURLCommand(url: URL(string: "notchfun://agent?state=dancing&session=x")!) == nil)
        #expect(NotchURLCommand(url: URL(string: "notchfun://agent?session=x")!) == nil)
    }
}
