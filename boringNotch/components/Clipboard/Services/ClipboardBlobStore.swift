//
//  ClipboardBlobStore.swift
//  boringNotch
//

import Foundation
import os

/// Backing store for clipboard payloads too large to keep inline in `index.json`.
///
/// One file per payload under `Clipboard/blobs/`. Files are written `0600` and the
/// directory `0700` — clipboard history is sensitive even after the password-manager
/// types are filtered out.
final class ClipboardBlobStore: Sendable {
    static let shared = ClipboardBlobStore()

    private static let logger = Logger(subsystem: "io.github.lookatsarthak.notchfun", category: "ClipboardBlobStore")

    let directory: URL
    let blobsDirectory: URL

    init(directory: URL? = nil) {
        let fm = FileManager.default
        let resolved: URL
        if let directory {
            resolved = directory
        } else {
            let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            resolved = (support ?? fm.temporaryDirectory)
                .appendingPathComponent("NotchFun", isDirectory: true)
                .appendingPathComponent("Clipboard", isDirectory: true)
        }
        self.directory = resolved
        self.blobsDirectory = resolved.appendingPathComponent("blobs", isDirectory: true)

        try? fm.createDirectory(
            at: blobsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // createDirectory only applies attributes to leaves it creates, so make sure
        // the parent is locked down too when it already existed.
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: resolved.path)
    }

    // MARK: - Read

    func data(for ref: ClipboardContentRef) -> Data? {
        if let inline = ref.inlineData { return inline }
        guard let filename = ref.blobFilename else { return nil }
        return try? Data(contentsOf: blobsDirectory.appendingPathComponent(filename))
    }

    // MARK: - Write

    /// Persists `data` and returns the blob filename, or `nil` if it should stay inline.
    func store(_ data: Data) -> String? {
        guard ClipboardContentRef.shouldSpillToBlob(data) else { return nil }

        let filename = "\(UUID().uuidString).bin"
        let url = blobsDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            // .atomic replaces the file, which drops the mode we asked for, so set it after.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return filename
        } catch {
            Self.logger.error("Failed to write clipboard blob: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Builds a content ref, spilling to a blob file when the payload is large.
    func makeRef(type: String, data: Data) -> ClipboardContentRef {
        ClipboardContentRef(type: type, data: data, blobFilename: store(data))
    }

    // MARK: - Cleanup

    func delete(_ refs: [ClipboardContentRef]) {
        let fm = FileManager.default
        for filename in refs.compactMap(\.blobFilename) {
            try? fm.removeItem(at: blobsDirectory.appendingPathComponent(filename))
        }
    }

    /// Removes blob files no longer referenced by any item. Guards against leaks from
    /// a crash between writing a blob and saving the index.
    func pruneOrphans(keeping items: [ClipboardItem]) {
        let fm = FileManager.default
        guard let present = try? fm.contentsOfDirectory(atPath: blobsDirectory.path) else { return }

        let referenced = Set(items.flatMap { $0.contents.compactMap(\.blobFilename) })
        var removed = 0
        for filename in present where !referenced.contains(filename) {
            try? fm.removeItem(at: blobsDirectory.appendingPathComponent(filename))
            removed += 1
        }
        if removed > 0 {
            Self.logger.info("Pruned \(removed, privacy: .public) orphaned clipboard blobs")
        }
    }

    func deleteAll() {
        let fm = FileManager.default
        try? fm.removeItem(at: blobsDirectory)
        try? fm.createDirectory(
            at: blobsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
