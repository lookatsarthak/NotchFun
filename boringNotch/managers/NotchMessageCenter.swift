//
//  NotchMessageCenter.swift
//  NotchFun
//

import AppKit
import Defaults
import Foundation

/// Shows `NotchMessage`s from Shortcuts and `notchfun://` links, and carries out the
/// link's other commands.
///
/// The newest message replaces whatever is showing; messages over the rate limit are
/// dropped. Nothing here opens, runs or fetches anything a message names.
@MainActor
@Observable
final class NotchMessageCenter {
    static let shared = NotchMessageCenter()

    /// The message the banner shows while it is up.
    private(set) var current: NotchMessage?

    @ObservationIgnored private var limiter = NotchMessageRateLimiter()

    private init() {}

    /// Returns false when the message was dropped: messages are off, or too many came in.
    @discardableResult
    func show(_ message: NotchMessage) -> Bool {
        guard Defaults[.allowNotchMessages], limiter.allow() else { return false }
        current = message
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .message)
        return true
    }

    /// Carries out a `notchfun://` link. Unknown or malformed links do nothing.
    func handle(_ url: URL) {
        guard let command = NotchURLCommand(url: url) else {
            NSLog("NotchFun: ignored link \(url.scheme ?? "")://\(url.host ?? "")")
            return
        }
        switch command {
        case .show(let message):
            show(message)
        case .open(let tab):
            NotchActions.openNotch(tab: tab.map(\.notchView), autoClose: true)
        case .close:
            NotchActions.closeNotch()
        case .agent(let report, let session):
            // Only while connected, so a stray link can't put "needs you" on the notch.
            guard ClaudeCodeConnection.shared.isConnected else { return }
            AgentStatusCenter.shared.handle(report, session: session)
        }
    }
}

private extension NotchURLCommand.Tab {
    var notchView: NotchViews {
        switch self {
        case .home: return .home
        case .shelf: return .shelf
        case .clipboard: return .clipboard
        }
    }
}
