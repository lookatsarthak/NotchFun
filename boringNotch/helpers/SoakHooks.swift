//
//  SoakHooks.swift
//  NotchFun
//

#if NOTCHFUN_SOAK
import AppKit

/// Remote controls for the release soak test. Compiled only into measurement builds
/// (`SWIFT_ACTIVE_COMPILATION_CONDITIONS=NOTCHFUN_SOAK`), never into a shipped one.
///
/// A fresh launch hides anything that grows with uptime: the 1.7 window leak only showed
/// after repeated screen locks. These let a script drive the paths that recreate or
/// exercise the notch, the same way every time, without touching the real lock screen
/// (other apps hear `com.apple.screenIsLocked` too) or the user's pointer.
///
/// Post `<bundle id>.soak.<command>` as a distributed notification; the object, if any,
/// is the argument.
///   lockcycle      run the lock handler, then the unlock handler 0.6 s later
///   displaychange  run the display-change handler as if the layout had changed
///   open [tab]     open the notch (home, shelf or clipboard) and keep it open
///   close          close the notch
///   shelfdemo      put demo files, a link and a text item on the shelf
///   settings P[@f] open Settings on pane P, scrolled to fraction f
///   repeat W[xN]   run UI path W (hud, sneak, battery, caffeine, openclose, tabs) N times
///   report         append one line of counts to <container tmp>/soak.log
enum SoakHooks {
    /// In-process: SettingsView switches to the pane named in the object.
    static let settingsPane = Notification.Name("NotchFunSoakSettingsPane")

    @MainActor
    static func install() {
        let prefix = (Bundle.main.bundleIdentifier ?? "notchfun") + ".soak."
        let center = DistributedNotificationCenter.default()
        func on(_ command: String, _ action: @escaping @MainActor (String?) -> Void) {
            center.addObserver(forName: Notification.Name(prefix + command), object: nil, queue: .main) { note in
                let argument = note.object as? String
                MainActor.assumeIsolated { action(argument) }
            }
        }

        on("lockcycle") { _ in
            guard let delegate = AppDelegate.shared else { return }
            delegate.onScreenLocked(Notification(name: Notification.Name("com.apple.screenIsLocked")))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                delegate.onScreenUnlocked(Notification(name: Notification.Name("com.apple.screenIsUnlocked")))
            }
        }
        // Plays a Claude Code state on the face without Claude Code: agentdemo working,
        // waiting, done, error or end, for session "demo" (or "demo2" with "@2").
        on("agentdemo") { argument in
            let parts = (argument ?? "working").split(separator: "@")
            guard let report = ClaudeCodeHooks.Report(rawValue: String(parts[0])) else { return }
            let session = parts.count > 1 ? "demo\(parts[1])" : "demo"
            AgentStatusCenter.shared.handle(report, session: session)
        }
        // Connects to a stand-in .claude folder inside the container, never the real one:
        // claudeconnect <path to a folder named .claude>, claudedisconnect.
        on("claudeconnect") { path in
            guard let path else { return }
            ClaudeCodeConnection.shared.connect(folder: URL(fileURLWithPath: path, isDirectory: true))
            appendToLog("\(Date().timeIntervalSince1970) claude connected=\(ClaudeCodeConnection.shared.isConnected) problem=\(ClaudeCodeConnection.shared.problem ?? "none")\n")
        }
        on("claudedisconnect") { _ in
            ClaudeCodeConnection.shared.disconnect()
            appendToLog("\(Date().timeIntervalSince1970) claude connected=\(ClaudeCodeConnection.shared.isConnected) problem=\(ClaudeCodeConnection.shared.problem ?? "none")\n")
        }
        // Opens the real Connect dialog, logs which folder it opened in, then cancels it.
        on("claudepanel") { _ in
            ClaudeCodeConnection.shared.connect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let panel = NSApp.windows.compactMap({ $0 as? NSOpenPanel }).first else {
                    appendToLog("panel none\n"); return
                }
                appendToLog("panel directory=\(panel.directoryURL?.path ?? "nil") visible=\(panel.isVisible)\n")
                panel.cancel(nil)
            }
        }
        on("lyricsdemo") { _ in
            MusicManager.shared.showDemoLyrics()
        }
        on("displaychange") { _ in
            AppDelegate.shared?.soakDisplayChange()
        }
        on("open") { argument in
            let tab: NotchViews? = switch argument {
            case "shelf": .shelf
            case "clipboard": .clipboard
            case "home": .home
            default: nil
            }
            NotchActions.openNotch(tab: tab, autoClose: false)
        }
        on("close") { _ in NotchActions.closeNotch() }
        // Repeats a short-lived UI path N times (default 100), 0.4 s apart, to show whether it
        // leaves anything behind: "hud", "sneak" (music sneak peek), "battery", "caffeine",
        // "openclose", "tabs".
        on("repeat") { argument in
            let parts = (argument ?? "hud").split(separator: "x")
            let what = String(parts[0])
            let times = parts.count > 1 ? Int(parts[1]) ?? 100 : 100
            let coordinator = BoringViewCoordinator.shared
            let tabs: [NotchViews] = [.home, .shelf, .clipboard]
            for i in 0..<times {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(i)) {
                    switch what {
                    case "hud":
                        coordinator.toggleSneakPeek(status: true, type: .volume, value: CGFloat(i % 10) / 10)
                    case "sneak":
                        coordinator.toggleSneakPeek(status: true, type: .music, duration: 0.3)
                    case "battery":
                        coordinator.toggleSneakPeek(status: true, type: .battery, value: 0.5)
                    case "caffeine":
                        _ = NotchActions.setCaffeine(i % 2 == 0 ? .on : .off)
                    case "openclose":
                        if i % 2 == 0 { NotchActions.openNotch(autoClose: false) } else { NotchActions.closeNotch() }
                    case "tabs":
                        NotchActions.openNotch(tab: tabs[i % 3], autoClose: false)
                    default: break
                    }
                }
            }
        }
        // "Pane" or "Pane@0.5": open Settings on that pane, scrolled that far down (0...1),
        // so every part of every pane can be captured even when the window is off-Space.
        on("settings") { argument in
            let parts = (argument ?? "General").split(separator: "@")
            let fraction = parts.count > 1 ? Double(parts[1]) ?? 0 : 0
            SettingsWindowController.shared.showWindow()
            // The view is built on show, so give it a moment to subscribe.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: settingsPane, object: String(parts[0]))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard let window = SettingsWindowController.shared.window,
                      let content = window.contentView else { return }
                func scrollViews(in view: NSView) -> [NSScrollView] {
                    (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(scrollViews)
                }
                // The detail pane's scroll view is the right-most one.
                guard let scroll = scrollViews(in: content).max(by: {
                    $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX
                }), let document = scroll.documentView else { return }
                let travel = max(0, document.frame.height - scroll.contentView.bounds.height)
                let y = document.isFlipped ? travel * fraction : travel * (1 - fraction)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        // Fills the shelf with whatever is in <container tmp>/demo-shelf, plus one link and
        // one text item, for screenshots that must not show anyone's real files.
        on("shelfdemo") { _ in
            let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("demo-shelf")
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            var items = files.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
                (try? Bookmark(url: url)).map { ShelfItem(kind: .file(bookmark: $0.data)) }
            }
            items.append(ShelfItem(kind: .link(url: URL(string: "https://lookatsarthak.github.io/NotchFun/")!)))
            items.append(ShelfItem(kind: .text(string: "Remember to stretch")))
            ShelfStateViewModel.shared.add(items)
        }
        // What the accessory battery manager holds, and what the power sources say, for
        // checking the AirPods path inside the sandbox. Names are not logged.
        on("accessory") { _ in
            let sources = AccessoryPowerSources.read()
            let parsed = sources.map(AccessoryPowerSourceParser.parse) ?? []
            func describe(_ reading: AccessoryBattery?) -> String {
                guard let reading else { return "nil" }
                return "level=\(reading.level) charging=\(reading.isCharging) parts=[\(reading.partsSummary)] nameMatchesOutput=\(reading.name == SystemAudioOutput.name())"
            }
            let line = "\(Date().timeIntervalSince1970) accessory sources=\(sources.map { String($0.count) } ?? "unreadable") parsed=\(parsed.count) outputIsBluetooth=\(SystemAudioOutput.isBluetooth()) current=\(describe(AccessoryBatteryManager.shared.current)) first=\(describe(parsed.first))\n"
            appendToLog(line)
        }
        // The first pair the power sources list, shown as if connected. Layout only.
        on("accessorydemo") { _ in
            guard let reading = AccessoryPowerSources.read().map(AccessoryPowerSourceParser.parse)?.first else { return }
            AccessoryBatteryManager.shared.showDemo(reading)
        }
        // A made-up call two minutes out, to show the meeting banner without a real calendar.
        on("meetingdemo") { title in
            MeetingReminder.shared.showDemo(title: title ?? "Design review")
        }
        on("report") { _ in
            let notchWindows = NSApp.windows.filter { $0 is BoringNotchSkyLightWindow }
            let line = "\(Date().timeIntervalSince1970) notchWindows=\(notchWindows.count) visible=\(notchWindows.filter(\.isVisible).count) appWindows=\(NSApp.windows.count) nowPlayingSource=\(MusicManager.shared.bundleIdentifier != nil)\n"
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("soak.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    @MainActor
    private static func appendToLog(_ line: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("soak.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
#endif
