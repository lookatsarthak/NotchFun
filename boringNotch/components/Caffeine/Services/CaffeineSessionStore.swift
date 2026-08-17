//
//  CaffeineSessionStore.swift
//  boringNotch
//

import Foundation

/// Persists the active session across launches.
///
/// A session must survive a quit or a crash: if caffeine was on and the app restarts,
/// the user expects it to still be on. Equally, a session that expired while the app
/// was not running must come back expired, which is why `CaffeineSession` stores an
/// absolute end time.
protocol CaffeineSessionStoring: AnyObject {
    func load() -> CaffeineSession?
    func save(_ session: CaffeineSession?)
}

final class CaffeineSessionStore: CaffeineSessionStoring {
    private let defaults: UserDefaults
    private let key = "caffeineActiveSession"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CaffeineSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CaffeineSession.self, from: data)
    }

    func save(_ session: CaffeineSession?) {
        guard let session else {
            defaults.removeObject(forKey: key)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }
        defaults.set(data, forKey: key)
    }
}

/// In-memory store for tests.
final class InMemoryCaffeineSessionStore: CaffeineSessionStoring {
    private var session: CaffeineSession?
    init(session: CaffeineSession? = nil) { self.session = session }
    func load() -> CaffeineSession? { session }
    func save(_ session: CaffeineSession?) { self.session = session }
}
