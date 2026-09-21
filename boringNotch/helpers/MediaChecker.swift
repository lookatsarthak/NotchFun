//
//  MediaChecker.swift
//  NotchFun
//
//  Created by Alexander on 2025-07-26.
//

import Foundation

final class MediaChecker: Sendable {

    enum MediaCheckerError: Error {
        case missingResources
        case processExecutionFailed
        case timeout
    }

    /// Cached across launches.
    ///
    /// The probe spawns perl plus a test client and waits up to ten seconds for it, on
    /// every single launch, to answer a question whose answer only changes when macOS or
    /// this app does. Keying the cache on both build strings means it re-runs exactly
    /// when it could have changed and never otherwise.
    private static var cacheKey: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let app = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(os)|\(app)"
    }

    private static let cacheKeyDefault = "mediaCheckerCacheKey"
    private static let cacheValueDefault = "mediaCheckerCachedResult"

    func cachedDeprecationStatus() -> Bool? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.cacheKeyDefault) == Self.cacheKey,
              defaults.object(forKey: Self.cacheValueDefault) != nil
        else { return nil }
        return defaults.bool(forKey: Self.cacheValueDefault)
    }

    func cacheDeprecationStatus(_ value: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(Self.cacheKey, forKey: Self.cacheKeyDefault)
        defaults.set(value, forKey: Self.cacheValueDefault)
    }

    func checkDeprecationStatus() async throws -> Bool {
        try await Task.detached(priority: .userInitiated) {
            guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
                  let nowPlayingTestClientPath = Bundle.main.url(forResource: "MediaRemoteAdapterTestClient", withExtension: nil)?.path,
                  let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
            else {
                throw MediaCheckerError.missingResources
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [scriptURL.path, frameworkPath, nowPlayingTestClientPath, "test"]

            do {
                try process.run()
            } catch {
                throw MediaCheckerError.processExecutionFailed
            }

            // Timeout after 10 seconds
            let didExit: Bool = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    process.waitUntilExit()
                    return true
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    if process.isRunning {
                        process.terminate()
                    }
                    return false // Timed out
                }
                for try await exited in group {
                    if exited {
                        group.cancelAll()
                        return true
                    }
                }
                throw MediaCheckerError.timeout
            }

            if !didExit {
                throw MediaCheckerError.timeout
            }

            let isDeprecated = process.terminationStatus == 1
            return isDeprecated
        }.value
    }
}
