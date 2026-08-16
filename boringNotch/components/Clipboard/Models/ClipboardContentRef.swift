//
//  ClipboardContentRef.swift
//  boringNotch
//

import AppKit.NSPasteboard
import CryptoKit
import Foundation

/// One pasteboard representation of a clip.
///
/// Small payloads are stored inline in `index.json`; anything larger is written to
/// `blobs/<uuid>.bin` and referenced by filename, so loading the index never pulls
/// image bytes into memory. `digest` lets deduplication compare 32-byte hashes
/// instead of full payloads — see `ClipboardItem.supersedes(_:)`.
struct ClipboardContentRef: Codable, Equatable, Hashable, Sendable {
    /// Payloads at or below this size are kept inline rather than spilled to a blob file.
    static let inlineByteLimit = 4 * 1024

    /// The pasteboard UTI, e.g. `public.utf8-plain-text`.
    let type: String
    /// Present only when the payload is small enough to live in the index.
    let inlineData: Data?
    /// Present only when the payload lives in `blobs/`.
    let blobFilename: String?
    let byteCount: Int
    /// Lowercase hex SHA-256 of the payload.
    let digest: String

    var pasteboardType: NSPasteboard.PasteboardType { NSPasteboard.PasteboardType(type) }

    var isInline: Bool { inlineData != nil }

    init(type: String, data: Data, blobFilename: String?) {
        self.type = type
        self.byteCount = data.count
        self.digest = Self.digest(of: data)
        if let blobFilename {
            self.inlineData = nil
            self.blobFilename = blobFilename
        } else {
            self.inlineData = data
            self.blobFilename = nil
        }
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func shouldSpillToBlob(_ data: Data) -> Bool {
        data.count > inlineByteLimit
    }
}
