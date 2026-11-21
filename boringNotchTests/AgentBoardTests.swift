//
//  AgentBoardTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Claude Code sessions on the face")
struct AgentBoardTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test("Nothing reported, nothing shown")
    func empty() {
        #expect(AgentBoard().headline == nil)
        #expect(AgentBoard().nextExpiry() == nil)
    }

    @Test("Waiting beats error beats working beats done")
    func urgency() {
        var board = AgentBoard()
        board.apply(state: .done, session: "a", at: t0)
        #expect(board.headline == .done)
        board.apply(state: .working, session: "b", at: t0)
        #expect(board.headline == .working)
        board.apply(state: .error, session: "c", at: t0)
        #expect(board.headline == .error)
        board.apply(state: .waiting, session: "d", at: t0)
        #expect(board.headline == .waiting)
        #expect(board.counts == [.done: 1, .working: 1, .error: 1, .waiting: 1])
    }

    @Test("A session moves through states and ends")
    func lifecycle() {
        var board = AgentBoard()
        board.apply(state: .working, session: "a", at: t0)
        board.apply(state: .waiting, session: "a", at: at(10))
        #expect(board.headline == .waiting)
        board.apply(state: .working, session: "a", at: at(20))
        board.apply(state: .done, session: "a", at: at(30))
        #expect(board.headline == .done)
        board.apply(state: nil, ended: true, session: "a", at: at(31))
        #expect(board.headline == nil)
    }

    @Test("Done shows for a few seconds, then goes quiet")
    func doneExpires() {
        var board = AgentBoard()
        board.apply(state: .done, session: "a", at: t0)
        #expect(board.nextExpiry() == at(AgentBoard.doneLifetime))
        let early = board.prune(at: at(AgentBoard.doneLifetime - 1))
        let onTime = board.prune(at: at(AgentBoard.doneLifetime))
        #expect(!early)
        #expect(onTime)
        #expect(board.headline == nil)
    }

    @Test("Long work stays working while tool calls keep coming")
    func longWork() {
        var board = AgentBoard()
        board.apply(state: .working, session: "a", at: t0)
        // A report every 10 minutes for an hour.
        for minute in stride(from: 10.0, through: 60, by: 10) {
            board.apply(state: .working, session: "a", at: at(minute * 60))
            board.prune(at: at(minute * 60 + 1))
            #expect(board.headline == .working)
        }
        #expect(board.sessions["a"]?.since == t0)
    }

    @Test("A session that dies mid-work stops showing after a long silence")
    func crashedSession() {
        var board = AgentBoard()
        board.apply(state: .working, session: "a", at: t0)
        board.prune(at: at(AgentBoard.workingLifetime - 1))
        #expect(board.headline == .working)
        board.prune(at: at(AgentBoard.workingLifetime))
        #expect(board.headline == nil)
    }

    @Test("Waiting outlasts a working session's silence, but not forever")
    func waitingLasts() {
        var board = AgentBoard()
        board.apply(state: .waiting, session: "a", at: t0)
        board.prune(at: at(AgentBoard.workingLifetime + 60))
        #expect(board.headline == .waiting)
        board.prune(at: at(AgentBoard.attentionLifetime))
        #expect(board.headline == nil)
    }
}
