//
//  ClipboardSnippet.swift
//  NotchFun
//

import Foundation

/// A saved piece of text with a name, made in Settings → Clipboard, that pastes from the
/// clipboard tab: start typing its name (or any of its text) and it's at the top of the
/// results, ready for Return or ⌘1.
///
/// Snippets show only while you type, never in the plain list, so ⌘1–⌘9 keep meaning
/// "the last nine things I copied".
struct ClipboardSnippet: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var text: String

    /// The snippet as a clipboard entry, so it goes through the same search, selection
    /// and paste as everything else. Never stored in the history.
    var asItem: ClipboardItem {
        var item = ClipboardItem(id: id, contents: [], title: name, kind: .text)
        item.snippetText = text
        return item
    }
}
