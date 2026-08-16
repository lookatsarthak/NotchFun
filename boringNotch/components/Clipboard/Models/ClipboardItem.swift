//
//  ClipboardItem.swift
//  boringNotch
//
//  Content accessors, title generation and the supersedes/dedupe rule are adapted
//  from Maccy (https://github.com/p0deje/Maccy), Maccy/Models/HistoryItem.swift.
//  MIT License © Alex Rodionov. See THIRD_PARTY_LICENSES.
//

import AppKit
import Foundation

/// One entry in the clipboard history.
///
/// This is pure `Codable` metadata — it holds no payload bytes beyond small inline
/// ones. Anything large is fetched on demand from `ClipboardBlobStore`, which keeps
/// `index.json` cheap to load at launch even with hundreds of image clips.
struct ClipboardItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var contents: [ClipboardContentRef]
    var title: String
    var kind: ClipboardKind
    /// Bundle identifier of the app that was frontmost when the copy happened.
    var appBundleID: String?
    var firstCopiedAt: Date
    var lastCopiedAt: Date
    var numberOfCopies: Int
    /// A single character used as the quick-select shortcut while pinned. `nil` = unpinned.
    var pin: String?

    var isPinned: Bool { pin != nil }

    init(
        id: UUID = UUID(),
        contents: [ClipboardContentRef],
        title: String,
        kind: ClipboardKind,
        appBundleID: String? = nil,
        firstCopiedAt: Date = .now,
        lastCopiedAt: Date = .now,
        numberOfCopies: Int = 1,
        pin: String? = nil
    ) {
        self.id = id
        self.contents = contents
        self.title = title
        self.kind = kind
        self.appBundleID = appBundleID
        self.firstCopiedAt = firstCopiedAt
        self.lastCopiedAt = lastCopiedAt
        self.numberOfCopies = numberOfCopies
        self.pin = pin
    }

    // MARK: - Equality and dedupe

    /// Two items are the same clip if every non-transient representation of `other`
    /// is present here with an identical payload.
    ///
    /// Compares SHA-256 digests rather than raw bytes (Maccy compares `Data`
    /// directly), so this never loads a blob from disk.
    func supersedes(_ other: ClipboardItem) -> Bool {
        let comparable = other.contents.filter {
            !ClipboardPasteboardTypes.transientForComparison.contains($0.type)
        }
        guard !comparable.isEmpty else { return false }
        return comparable.allSatisfy { candidate in
            contents.contains { $0.type == candidate.type && $0.digest == candidate.digest }
        }
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Content access

    func ref(for types: [NSPasteboard.PasteboardType]) -> ClipboardContentRef? {
        contents.first { types.contains($0.pasteboardType) }
    }

    func refs(for types: [NSPasteboard.PasteboardType]) -> [ClipboardContentRef] {
        contents.filter { types.contains($0.pasteboardType) }
    }

    func data(for types: [NSPasteboard.PasteboardType], using store: ClipboardBlobStore) -> Data? {
        ref(for: types).flatMap { store.data(for: $0) }
    }

    func text(using store: ClipboardBlobStore) -> String? {
        guard let data = data(for: [.string, .utf8PlainText], using: store) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func rtf(using store: ClipboardBlobStore) -> NSAttributedString? {
        guard let data = data(for: [.rtf], using: store) else { return nil }
        return NSAttributedString(rtf: data, documentAttributes: nil)
    }

    func html(using store: ClipboardBlobStore) -> NSAttributedString? {
        guard let data = data(for: [.html], using: store) else { return nil }
        return NSAttributedString(html: data, documentAttributes: nil)
    }

    func imageData(using store: ClipboardBlobStore) -> Data? {
        data(for: ClipboardPasteboardTypes.image, using: store)
    }

    func fileURLs(using store: ClipboardBlobStore) -> [URL] {
        refs(for: [.fileURL])
            .compactMap { store.data(for: $0) }
            .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
    }

    var isFromNotchFun: Bool {
        contents.contains { $0.pasteboardType == .fromNotchFun }
    }

    var isUniversalClipboard: Bool {
        contents.contains { $0.pasteboardType == .universalClipboard }
    }

    // MARK: - Title

    /// Longest character count considered when building a title. Beyond this the
    /// cost of attributed-string work outweighs any benefit, since the row shows
    /// a single truncated line.
    static let titleCharacterLimit = 1_000

    /// Builds the one-line label shown in the list.
    ///
    /// Uses the app's existing `getAttributedString(content:type:)` helper for the
    /// rich-text cases so rtf/html/webarchive clips get readable titles rather than
    /// markup.
    static func makeTitle(
        contents: [ClipboardContentRef],
        kind: ClipboardKind,
        resolve: (ClipboardContentRef) -> Data?
    ) -> String {
        if kind == .files {
            let paths = contents
                .filter { $0.pasteboardType == .fileURL }
                .compactMap { resolve($0) }
                .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
                .compactMap { $0.absoluteString.removingPercentEncoding }
            if !paths.isEmpty {
                return paths.joined(separator: "  ")
            }
        }

        let preferred: [NSPasteboard.PasteboardType] = [.string, .utf8PlainText, .rtf, .html, .webArchive]
        for type in preferred {
            guard let ref = contents.first(where: { $0.pasteboardType == type }),
                  let data = resolve(ref) else { continue }

            let candidate: String?
            if type == .string || type == .utf8PlainText {
                candidate = String(data: data, encoding: .utf8)
            } else {
                candidate = getAttributedString(content: data, type: type)?.string
            }

            if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return normalizeTitle(candidate)
            }
        }

        return ""
    }

    private static func normalizeTitle(_ raw: String) -> String {
        String(raw.prefix(titleCharacterLimit))
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Classifies a clip from the pasteboard types it carries.
    static func makeKind(contents: [ClipboardContentRef], title: String) -> ClipboardKind {
        let types = Set(contents.map(\.pasteboardType))
        if !ClipboardPasteboardTypes.image.filter(types.contains).isEmpty { return .image }
        if types.contains(.fileURL) { return .files }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(" "), let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return .link
        }
        return .text
    }
}
