//
//  ClipboardThumbnailService.swift
//  boringNotch
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Produces row-sized thumbnails for image clips, and caches app icons.
///
/// Uses `CGImageSourceCreateThumbnailAtIndex`, which decodes straight to the target
/// size — a 20 MB screenshot never becomes a 20 MB `NSImage` just to draw a 40pt row.
/// (Maccy resizes a fully decoded `NSImage`, which is where image history tends to eat
/// memory.) Blob-backed payloads are read by URL so the bytes never pass through the
/// heap at all.
@MainActor
final class ClipboardThumbnailService {
    static let shared = ClipboardThumbnailService()

    private let cache = NSCache<NSString, NSImage>()
    private let iconCache = NSCache<NSString, NSImage>()
    private let blobStore: ClipboardBlobStore

    init(blobStore: ClipboardBlobStore = .shared) {
        self.blobStore = blobStore
        cache.totalCostLimit = 32 * 1024 * 1024
        iconCache.countLimit = 64
    }

    // MARK: - Thumbnails

    func thumbnail(for item: ClipboardItem, maxPixelSize: CGFloat) -> NSImage? {
        guard item.kind == .image else { return nil }
        let key = "\(item.id.uuidString)-\(Int(maxPixelSize))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let ref = item.ref(for: ClipboardPasteboardTypes.image),
              let source = makeImageSource(for: ref) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize * 2 // retina
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    private func makeImageSource(for ref: ClipboardContentRef) -> CGImageSource? {
        if let filename = ref.blobFilename {
            let url = blobStore.blobsDirectory.appendingPathComponent(filename)
            return CGImageSourceCreateWithURL(url as CFURL, nil)
        }
        guard let data = ref.inlineData else { return nil }
        return CGImageSourceCreateWithData(data as CFData, nil)
    }

    func forget(_ item: ClipboardItem) {
        // Sizes are few and fixed, so clearing the known ones is cheaper than tracking keys.
        for size in [20, 40, 228] {
            cache.removeObject(forKey: "\(item.id.uuidString)-\(size)" as NSString)
        }
    }

    // MARK: - App icons

    func appIcon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        let key = bundleID as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache.setObject(icon, forKey: key)
        return icon
    }
}
