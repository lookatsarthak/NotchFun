//
//  ImageService.swift
//  NotchFun
//
//  Created by Alexander on 2025-09-13.
//

import Foundation
import Defaults

public protocol ImageServiceProtocol {
    func fetchImageData(from url: URL) async throws -> Data
}

public final class ImageService: ImageServiceProtocol {
    public static let shared = ImageService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        let cache = URLCache(memoryCapacity: 50 * 1024 * 1024, // 50MB
                             diskCapacity: 100 * 1024 * 1024, // 100MB
                             diskPath: "artwork_cache")
        config.urlCache = cache
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)

        performLegacyCacheCleanupIfNeeded()
    }

    private func performLegacyCacheCleanupIfNeeded() {

        if !Defaults[.didClearLegacyURLCacheV1] {
            URLCache.shared.removeAllCachedResponses()
            Defaults[.didClearLegacyURLCacheV1] = true
        }
    }

    public func fetchImageData(from url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw URLError(.unsupportedURL)
        }
        // App Transport Security blocks plain HTTP. Spotify has handed out http:// artwork
        // links for images its CDN also serves over HTTPS, so ask for those securely.
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        guard let secureURL = components?.url else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: secureURL)
        return data
    }
}
