//
//  ClipboardCaptureConfig.swift
//  boringNotch
//

import Foundation

/// Everything the capture pipeline needs to know, resolved from `Defaults` by the
/// view model and passed in as a plain value.
///
/// Keeping the monitor free of `Defaults` means the capture and dedupe rules can be
/// exercised in isolation, and it keeps preference reads off the polling hot path.
struct ClipboardCaptureConfig: Equatable, Sendable {
    /// How often to compare `NSPasteboard.changeCount`.
    var pollInterval: TimeInterval = 0.5
    /// Maximum number of unpinned entries kept. Pinned entries are exempt.
    var maxHistorySize: Int = 200
    /// Payloads larger than this are dropped rather than stored, so a rogue copy
    /// can't write hundreds of megabytes into the history.
    var maxPayloadBytes: Int = 32 * 1024 * 1024
    /// Skip clips that arrived over Universal Clipboard from another device.
    var ignoreUniversalClipboard: Bool = false
    /// Skip text that looks like a password or token even when the app that copied it
    /// set no marker. A guess, so it is off unless the user turns it on.
    var skipSensitiveText: Bool = false
    /// Bundle identifiers whose copies are never recorded.
    var ignoredAppBundleIDs: Set<String> = []

    static let `default` = ClipboardCaptureConfig()
}
