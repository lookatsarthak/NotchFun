//
//  TestSupport.swift
//  boringNotchTests
//

import AppKit
import Foundation

/// A throwaway directory for a single test.
///
/// Every test gets its own, because swift-testing runs tests in parallel by default and
/// a shared blob directory would let one test's `pruneOrphans` delete another's files.
func makeTemporaryDirectory(_ label: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("notchfun-\(label)-\(UUID().uuidString)", isDirectory: true)
}

func removeDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

func posixPermissions(of path: String) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    return (attributes[.posixPermissions] as! NSNumber).intValue
}

extension JSONEncoder {
    static var notchFunISO8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var notchFunISO8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Stands in for a real `IOPMAssertion` so tests never actually stop this Mac sleeping.
///
/// Mirrors the real implementation's replace-don't-stack behaviour, since that is the
/// invariant most of the manager tests are checking.
final class FakeAssertion: PowerAssertionHolding {
    var isHeld = false
    var holdCount = 0
    var releaseCount = 0
    var lastMode: CaffeineMode?
    /// Set to simulate the kernel refusing to give us an assertion.
    var shouldFail = false

    func hold(mode: CaffeineMode, reason: String) -> Bool {
        if shouldFail { return false }
        if isHeld { releaseCount += 1 }
        isHeld = true
        holdCount += 1
        lastMode = mode
        return true
    }

    func release() {
        if isHeld { releaseCount += 1 }
        isHeld = false
    }
}

/// A fixed reference point, so nothing depends on the wall clock.
let testEpoch = Date(timeIntervalSince1970: 1_700_000_000)
