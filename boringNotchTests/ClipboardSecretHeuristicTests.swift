//
//  ClipboardSecretHeuristicTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Clipboard secret heuristic")
struct ClipboardSecretHeuristicTests {
    @Test("Recognises labelled credentials", arguments: [
        "password: hunter2000",
        "PASSWORD=correcthorse",
        "api_key: 8f3a9c2b7e1d",
        "Authorization: Bearer abc123def456",
        "client_secret=zK9x2Lm4Qp",
    ])
    func labelled(text: String) {
        #expect(ClipboardSecretHeuristic.looksSensitive(text))
    }

    @Test("Recognises credentials by their issued prefix", arguments: [
        "sk-abc123def456ghi",
        "ghp_16CharsAtLeastHere",
        "AKIAIOSFODNN7EXAMPLE",
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
        "-----BEGIN OPENSSH PRIVATE KEY-----",
    ])
    func prefixes(text: String) {
        #expect(ClipboardSecretHeuristic.looksSensitive(text))
    }

    @Test("Leaves ordinary text alone", arguments: [
        "I forgot my password again",
        "the password is on the whiteboard",
        "Reset your password by clicking the link we sent",
        "token",
        "password:",
        "secret sauce recipe",
        "12345678",
        "https://example.com/reset-password",
    ])
    func prose(text: String) {
        // Losing a copy the user wanted is worse than keeping one they did not think
        // about, so anything that reads as a sentence has to survive.
        #expect(!ClipboardSecretHeuristic.looksSensitive(text))
    }

    @Test("Ignores anything long enough to be a document")
    func longText() {
        let essay = String(repeating: "password: notreally ", count: 60)
        #expect(!ClipboardSecretHeuristic.looksSensitive(essay))
    }

    @Test("Empty and whitespace are not secrets")
    func empty() {
        #expect(!ClipboardSecretHeuristic.looksSensitive(""))
        #expect(!ClipboardSecretHeuristic.looksSensitive("   \n\t "))
    }
}
