//
//  ClipboardCapture.swift
//  boringNotch
//
//  The filtering rules here are adapted from Maccy (https://github.com/p0deje/Maccy),
//  Maccy/Clipboard.swift. MIT License © Alex Rodionov.
//  See THIRD_PARTY_LICENSES.
//

import AppKit
import Foundation

/// Turns the current pasteboard contents into a `ClipboardItem`, or decides it should
/// not be recorded at all.
///
/// Stateless and free of `Defaults`, so the rules can be exercised against a scratch
/// `NSPasteboard` in isolation.
enum ClipboardCapture {

    /// True when the copy must not be recorded under any circumstance.
    ///
    /// Reads the union of types across the whole pasteboard rather than per item — a
    /// concealed marker anywhere means the entire copy is off limits. This is what
    /// keeps password managers out of the history.
    static func shouldIgnore(pasteboardTypes types: Set<NSPasteboard.PasteboardType>) -> Bool {
        if !types.isDisjoint(with: ClipboardPasteboardTypes.ignored) { return true }
        if types.contains(where: { ClipboardPasteboardTypes.ignoredRawValues.contains($0.rawValue) }) { return true }
        return false
    }

    /// Raw pasteboard payloads, lifted off the pasteboard but not yet hashed or
    /// written to disk.
    struct Snapshot: Sendable {
        struct Payload: Sendable {
            let type: String
            let data: Data
        }
        let payloads: [Payload]
        let appBundleID: String?
    }

    /// Reads the pasteboard. **Must run on the main actor**, and is deliberately cheap:
    /// nothing here hashes, resizes or touches the disk.
    ///
    /// Splitting the read from the processing matters twice over. It keeps a large
    /// image copy from blocking the main thread while the notch is animating, and it
    /// keeps the poll tick short — a long tick means the next one is skipped, and a
    /// skipped tick loses any clip copied in the meantime, because the pasteboard only
    /// ever reports its *current* contents.
    static func snapshot(
        from pasteboard: NSPasteboard,
        sourceAppBundleID: String?,
        config: ClipboardCaptureConfig
    ) -> Snapshot? {
        let allTypes = Set(pasteboard.types ?? [])
        guard !shouldIgnore(pasteboardTypes: allTypes) else { return nil }

        // Our own paste wrote this; recording it would duplicate the entry the user
        // just selected and, over time, degenerate the history.
        guard !allTypes.contains(.fromNotchFun) else { return nil }

        if config.ignoreUniversalClipboard && allTypes.contains(.universalClipboard) {
            return nil
        }

        var payloads: [Snapshot.Payload] = []

        // Some apps (BBEdit, Edge) write several pasteboard items for a single copy.
        // Merge them into one entry rather than recording each separately.
        for element in pasteboard.pasteboardItems ?? [] {
            let elementTypes = Set(element.types)
            guard !shouldIgnore(pasteboardTypes: elementTypes) else { continue }

            // A plain-text item with nothing in it and no rich alternative is noise.
            if elementTypes.contains(.string), isEmptyText(element), !hasRichText(elementTypes) {
                continue
            }

            for type in resolvedTypes(for: elementTypes) {
                guard let data = element.data(forType: type), !data.isEmpty else { continue }
                guard data.count <= config.maxPayloadBytes else { continue }
                payloads.append(Snapshot.Payload(type: type.rawValue, data: data))
            }
        }

        guard !payloads.isEmpty else { return nil }
        return Snapshot(payloads: payloads, appBundleID: sourceAppBundleID)
    }

    /// Hashes the payloads, spills large ones to blob files and derives the title.
    /// Safe to call off the main actor.
    static func makeItem(from snapshot: Snapshot, blobStore: ClipboardBlobStore) -> ClipboardItem? {
        let refs = snapshot.payloads.map { blobStore.makeRef(type: $0.type, data: $0.data) }
        guard !refs.isEmpty else { return nil }

        let title = ClipboardItem.makeTitle(contents: refs, kind: .text) { blobStore.data(for: $0) }
        let kind = ClipboardItem.makeKind(contents: refs, title: title)

        // A clip with no representable content and no title would render as a blank row.
        guard !title.isEmpty || kind == .image else {
            blobStore.delete(refs)
            return nil
        }

        return ClipboardItem(
            contents: refs,
            title: title,
            kind: kind,
            appBundleID: snapshot.appBundleID
        )
    }

    // MARK: - Type selection

    /// Narrows a pasteboard item's advertised types down to the ones worth storing.
    ///
    /// Diverges from Maccy deliberately: Maccy persists nearly every type so a paste
    /// reproduces the original pasteboard byte for byte. NotchFun keeps only the
    /// supported set plus the Universal Clipboard marker, because the history lives
    /// beside an always-resident UI and disk/memory cost matters more here than
    /// perfect fidelity when pasting into rich editors.
    static func resolvedTypes(for types: Set<NSPasteboard.PasteboardType>) -> [NSPasteboard.PasteboardType] {
        var selected = types.filter { type in
            guard !ClipboardPasteboardTypes.isNoise(type.rawValue) else { return false }
            return ClipboardPasteboardTypes.supported.contains(type)
                || ClipboardPasteboardTypes.image.contains(type)
                || type == .universalClipboard
        }

        // A Word bookmark drags along a PDF rendering of the link that is large and
        // useless in a history list.
        if selected.isSuperset(of: [.microsoftLinkSource, .microsoftObjectLink]) {
            selected.subtract([.microsoftLinkSource, .microsoftObjectLink, .pdf])
        }

        // Stable order so two captures of the same clip produce identical refs.
        return selected.sorted { $0.rawValue < $1.rawValue }
    }

    private static func isEmptyText(_ element: NSPasteboardItem) -> Bool {
        guard let string = element.string(forType: .string) else { return true }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func hasRichText(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        !types.isDisjoint(with: [.rtf, .html, .fileURL])
            || !types.isDisjoint(with: Set(ClipboardPasteboardTypes.image))
    }
}
