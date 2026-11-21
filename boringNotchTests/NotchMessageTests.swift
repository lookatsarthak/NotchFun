//
//  NotchMessageTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Show in Notch: messages, links and rate limit")
struct NotchMessageTests {

    private func command(_ string: String) -> NotchURLCommand? {
        NotchURLCommand(url: URL(string: string)!)
    }

    // MARK: Messages

    @Test("A full show link")
    func fullLink() throws {
        let parsed = try #require(command("notchfun://show?text=Build%20passed&icon=checkmark.circle.fill&progress=0.4&seconds=6"))
        let expected = try #require(NotchMessage(text: "Build passed", symbol: "checkmark.circle.fill", progress: 0.4, seconds: 6))
        #expect(parsed == .show(expected))
    }

    @Test("Defaults: no icon, no progress, four seconds")
    func defaults() throws {
        guard case .show(let message) = try #require(command("notchfun://show?text=Hi")) else {
            Issue.record("not a show command"); return
        }
        #expect(message.symbol == nil)
        #expect(message.progress == nil)
        #expect(message.seconds == NotchMessage.defaultSeconds)
    }

    @Test("Text is flattened to one clean line")
    func oneLine() throws {
        let message = try #require(NotchMessage(text: "  Deploy\n\tfinished \u{0007}in  3 min\u{202E}  "))
        #expect(message.text == "Deploy finished in 3 min")
    }

    @Test("Emoji, including joined ones, survive")
    func emoji() throws {
        let message = try #require(NotchMessage(text: "Shipped 🚀 by 👩‍💻"))
        #expect(message.text == "Shipped 🚀 by 👩‍💻")
    }

    @Test("Long text is cut to the limit with an ellipsis")
    func longText() throws {
        let message = try #require(NotchMessage(text: String(repeating: "a", count: 200)))
        #expect(message.text.count == NotchMessage.maxTextLength)
        #expect(message.text.hasSuffix("…"))
    }

    @Test("Empty or blank text is refused")
    func empty() {
        #expect(NotchMessage(text: "") == nil)
        #expect(NotchMessage(text: " \n\t ") == nil)
        #expect(command("notchfun://show") == nil)
        #expect(command("notchfun://show?icon=star") == nil)
    }

    @Test("Seconds and progress are kept in bounds")
    func bounds() throws {
        #expect(NotchMessage(text: "x", seconds: 0.1)?.seconds == 1)
        #expect(NotchMessage(text: "x", seconds: 999)?.seconds == 30)
        #expect(NotchMessage(text: "x", seconds: .nan)?.seconds == NotchMessage.defaultSeconds)
        #expect(NotchMessage(text: "x", progress: 1.7)?.progress == 1)
        #expect(NotchMessage(text: "x", progress: -1)?.progress == 0)
        #expect(NotchMessage(text: "x", progress: .infinity)?.progress == nil)
        guard case .show(let percent) = try #require(command("notchfun://show?text=x&progress=40%25")) else { return }
        #expect(percent.progress == 0.4)
    }

    @Test("Only real-looking symbol names pass", arguments: [
        ("checkmark.circle.fill", "checkmark.circle.fill"),
        ("Star", "star"),
        ("../../etc/passwd", nil),
        ("https://example.com/x.png", nil),
        ("a..b", nil),
        (".hidden", nil),
        ("cloud.sun.rain 2", nil),
    ] as [(String, String?)])
    func symbols(_ raw: String, _ expected: String?) {
        #expect(NotchMessage(text: "x", symbol: raw)?.symbol == expected)
    }

    // MARK: Other commands

    @Test("Open, open on a tab, close")
    func openClose() {
        #expect(command("notchfun://open") == .open(nil))
        #expect(command("notchfun://open?tab=Shelf") == .open(.shelf))
        #expect(command("notchfun://close") == .close)
        #expect(command("NOTCHFUN://close") == .close)
    }

    @Test("Unknown actions, tabs and schemes are refused")
    func refused() {
        #expect(command("notchfun://open?tab=settings") == nil)
        #expect(command("notchfun://delete?all=1") == nil)
        #expect(command("https://show?text=hi") == nil)
        #expect(command("notchfun://") == nil)
    }

    @Test("The first value wins when a parameter repeats")
    func repeatedParameter() throws {
        guard case .show(let message) = try #require(command("notchfun://show?text=one&text=two")) else { return }
        #expect(message.text == "one")
    }

    // MARK: Rate limit

    @Test("Five per ten seconds, then drop until the window moves on")
    func rateLimit() {
        var limiter = NotchMessageRateLimiter(limit: 5, window: 10)
        let start = Date(timeIntervalSince1970: 1_000)
        let allowed = (0..<7).map { limiter.allow(at: start.addingTimeInterval(Double($0) * 0.5)) }
        #expect(allowed == [true, true, true, true, true, false, false])
        let later = [10, 10.2, 11].map { limiter.allow(at: start.addingTimeInterval($0)) }
        #expect(later == [true, false, true])
    }
}
