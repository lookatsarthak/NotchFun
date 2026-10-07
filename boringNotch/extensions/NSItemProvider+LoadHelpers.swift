//
//  NSItemProvider+LoadHelpers.swift
//  NotchFun
//
//  Created by Alexander on 2025-09-24.
//


import AppKit
import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    
    func extractItem() async -> URL? {
        return await loadFileURL(typeIdentifier: UTType.item.identifier)
    }

    
    /// Detects if this is a file dragged from the filesystem
    func extractFileURL() async -> URL? {
        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await loadFileURL(typeIdentifier: UTType.fileURL.identifier)
        }
        return nil
    }
    
    /// What a provider hands over as raw data.
    enum DroppedData {
        /// The bytes themselves (an image copied out of an app, say).
        case bytes(Data)
        /// A file a promise was written to, in a temporary folder its sender cleans up:
        /// a screenshot's floating thumbnail, a Mail attachment, an image from a browser.
        case promisedFile(URL)
    }

    /// Loads raw data, or the file a file promise was written to.
    ///
    /// A promise used to arrive in SwiftUI's own `com.apple.SwiftUI.filePromises` folder, and
    /// anything else was taken for an ordinary file and left to `extractItem()`, which only
    /// points at it. macOS now delivers the sender's own temporary copy instead (for a
    /// screenshot thumbnail, screencaptureui's `TemporaryItems/NSIRD_…` folder), so every
    /// transient location counts as a promise here and the caller keeps a copy. Ordinary
    /// files still return nil, to be referenced rather than duplicated.
    func loadData() async -> DroppedData? {
        guard hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<DroppedData?, Never>) in
            loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { item, error in
                if let error = error {
                    print("Error loading data for type \(UTType.data.identifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                } else if let url = item as? URL {
                    cont.resume(returning: url.isTransientDropLocation ? .promisedFile(url) : nil)
                } else if let data = item as? Data {
                    cont.resume(returning: .bytes(data))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Attempts to extract a URL (web link) from the provider
    func extractURL() async -> URL? {
        if self.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(typeIdentifier: UTType.url.identifier) {
                //Validate URL
                guard url.scheme != nil else { return nil }
                return url
            }
        }

        return nil
    }

    func extractText() async -> String? {
        let textTypes = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]

        for typeIdentifier in textTypes where self.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let text = await loadText(typeIdentifier: typeIdentifier) {
                return text
            }
        }

        return nil
    }

    /// Loads a file URL from the provider for the given type identifier.
    func loadFileURL(typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error = error {
                    print("❌ Error loading item for type \(typeIdentifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                var resolvedURL: URL?
                if let url = item as? URL {
                    // Direct URL provided
                    resolvedURL = url
                } else if let data = item as? Data {
                    // Some providers hand out a UTF-8 file URL string, others a bookmark. Prefer parsing string first.
                    if let string = String(data: data, encoding: .utf8) {
                        if let url = URL(string: string) {
                            resolvedURL = url
                        } else if string.hasPrefix("/") {
                            // Plain file system path
                            resolvedURL = URL(fileURLWithPath: string)
                        }
                    }
                    if resolvedURL == nil {
                        // Fallback: try treating the data as a bookmark
                        let bookmark = Bookmark(data: data)
                        resolvedURL = bookmark.resolveURL()
                    }
                } else if let string = item as? String {
                    if let url = URL(string: string) {
                        resolvedURL = url
                    } else if string.hasPrefix("/") {
                        resolvedURL = URL(fileURLWithPath: string)
                    }
                }
                cont.resume(returning: resolvedURL)
            }
        }
    }

    /// Loads a URL from the provider for the given type identifier.
    func loadURL(typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    cont.resume(returning: nil)
                    return
                }

                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let data = item as? Data {
                    if let string = String(data: data, encoding: .utf8) {
                        if let url = URL(string: string) {
                            cont.resume(returning: url)
                            return
                        } else if string.hasPrefix("/") {
                            cont.resume(returning: URL(fileURLWithPath: string))
                            return
                        }
                    }
                    cont.resume(returning: nil)
                } else if let string = item as? String {
                    if let url = URL(string: string) {
                        cont.resume(returning: url)
                    } else if string.hasPrefix("/") {
                        cont.resume(returning: URL(fileURLWithPath: string))
                    } else {
                        cont.resume(returning: nil)
                    }
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Loads text from the provider for the given type identifier.
    func loadText(typeIdentifier: String) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    cont.resume(returning: nil)
                    return
                }

                if let string = item as? String {
                    cont.resume(returning: string)
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8) {
                    cont.resume(returning: string)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
