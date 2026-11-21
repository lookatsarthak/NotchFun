//
//  NotchMessage.swift
//  NotchFun
//

import Foundation

/// A short line shown in the closed notch for a few seconds, sent from Shortcuts or a
/// `notchfun://show` link: build passed, a stock price, the weather, anything a script
/// knows.
///
/// Text only, by design. Anything on the Mac can open a `notchfun://` link, so a message
/// can't open, run or fetch anything, and everything in it is cleaned up here: one line,
/// no control characters, a length limit, a symbol name that is only a symbol name, and
/// a duration within bounds.
struct NotchMessage: Hashable, Sendable {
    static let maxTextLength = 80
    static let secondsRange: ClosedRange<Double> = 1...30
    static let defaultSeconds: Double = 4

    /// One line, at most `maxTextLength` characters.
    let text: String
    /// An SF Symbol name, if it looks like one. The view still checks it exists.
    let symbol: String?
    /// 0...1, drawn as a ring.
    let progress: Double?
    let seconds: Double

    init?(text: String, symbol: String? = nil, progress: Double? = nil, seconds: Double? = nil) {
        let line = Self.oneLine(text)
        guard !line.isEmpty else { return nil }
        self.text = line.count > Self.maxTextLength
            ? String(line.prefix(Self.maxTextLength - 1)) + "…"
            : line
        self.symbol = symbol.flatMap(Self.validSymbol)
        self.progress = progress.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }
        let seconds = seconds.flatMap { $0.isFinite ? $0 : nil } ?? Self.defaultSeconds
        self.seconds = min(max(seconds, Self.secondsRange.lowerBound), Self.secondsRange.upperBound)
    }

    /// Newlines and tabs become spaces, other control and format characters go, and runs
    /// of spaces collapse.
    private static func oneLine(_ text: String) -> String {
        var out = ""
        var lastWasSpace = true
        for scalar in text.unicodeScalars {
            let props = scalar.properties
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else if props.generalCategory == .control
                        || (props.generalCategory == .format && scalar.value != 0x200D) {
                // Dropped. The zero-width joiner stays, or 👩‍💻 falls apart.
                continue
            } else {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// "checkmark.circle.fill" yes; paths, URLs and anything else no.
    private static func validSymbol(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, name.count <= 64,
              name.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "." }),
              !name.hasPrefix("."), !name.hasSuffix("."), !name.contains("..")
        else { return nil }
        return name
    }
}

/// What a `notchfun://` link asks for.
///
/// - `notchfun://show?text=Build%20passed&icon=checkmark.circle&progress=0.4&seconds=5`
/// - `notchfun://open` or `notchfun://open?tab=shelf` (home, shelf, clipboard)
/// - `notchfun://close`
enum NotchURLCommand: Equatable, Sendable {
    enum Tab: String, Sendable { case home, shelf, clipboard }

    case show(NotchMessage)
    case open(Tab?)
    case close

    static let scheme = "notchfun"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        // notchfun://show is host "show"; notchfun:show and notchfun:///show are tolerated.
        let action = (components.host ?? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name.lowercased()] == nil {
            query[item.name.lowercased()] = item.value ?? ""
        }

        switch action {
        case "show":
            guard let message = NotchMessage(
                text: query["text"] ?? "",
                symbol: query["icon"] ?? query["symbol"],
                progress: query["progress"].flatMap(Self.progress),
                seconds: query["seconds"].flatMap(Double.init)
            ) else { return nil }
            self = .show(message)
        case "open":
            if let raw = query["tab"], !raw.isEmpty {
                guard let tab = Tab(rawValue: raw.lowercased()) else { return nil }
                self = .open(tab)
            } else {
                self = .open(nil)
            }
        case "close":
            self = .close
        default:
            return nil
        }
    }

    /// "0.4" or "40%".
    private static func progress(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("%") { return Double(text.dropLast()).map { $0 / 100 } }
        return Double(text)
    }
}

/// At most `limit` messages per `window`, so a runaway script or a page opening links in
/// a loop can't keep the notch flashing. Excess messages are dropped, not queued.
struct NotchMessageRateLimiter: Sendable {
    let limit: Int
    let window: TimeInterval
    private var recent: [Date] = []

    init(limit: Int = 5, window: TimeInterval = 10) {
        self.limit = limit
        self.window = window
    }

    mutating func allow(at now: Date = Date()) -> Bool {
        recent.removeAll { now.timeIntervalSince($0) >= window }
        guard recent.count < limit else { return false }
        recent.append(now)
        return true
    }
}
