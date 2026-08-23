//
//  ClipboardSecretHeuristic.swift
//  boringNotch
//

import Foundation

/// A guess at whether copied text is a credential.
///
/// The reliable signal is the nspasteboard concealed marker, and that is always
/// honoured. This is for everything that never sets it: a token copied out of a
/// terminal, an API key from a web page, a password pasted from a document. Those
/// otherwise land in the history file in plain text.
///
/// It is a guess, which is why it is off by default and why the wording in Settings
/// says so. Two rules have to agree before anything is skipped - a label saying what
/// the value is, and a value that actually looks like a secret - because "my password
/// is hopeless" is a sentence, not a credential.
enum ClipboardSecretHeuristic {
    /// Words that introduce a credential.
    private static let labels = [
        "password", "passwd", "pwd", "secret", "token", "apikey", "api_key", "api-key",
        "authorization", "auth_token", "access_key", "private_key", "client_secret",
    ]

    /// Prefixes real credentials are issued with. These are conclusive on their own.
    private static let knownPrefixes = [
        "sk-", "pk-", "ghp_", "gho_", "ghu_", "ghs_", "github_pat_", "xox", "AKIA",
        "ASIA", "AIza", "eyJ", "-----BEGIN",
    ]

    static func looksSensitive(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Anything long enough to be prose is a note about a password, not one.
        guard trimmed.count <= 512 else { return false }

        if knownPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return true }

        // A link is not a credential, and links get copied constantly. "reset-password"
        // in a URL path would otherwise match, which would be maddening.
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") { return false }
        let hasLabel = labels.contains { lowered.contains($0) }
        guard hasLabel else { return false }

        // A label alone is not enough: it has to be followed by something that could
        // be a value, as in "password: hunter2" or "API_KEY=abc123".
        guard let separator = trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: ":=")) else {
            // No separator, so treat a single opaque word as the value itself.
            return !trimmed.contains(" ") && looksLikeValue(trimmed)
        }
        let value = trimmed[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        // "Authorization: Bearer abc123" carries the credential in the last word.
        let candidate = value.split(separator: " ").last.map(String.init) ?? value
        return looksLikeValue(candidate)
    }

    /// Whether a string looks like a credential rather than a phrase: one opaque run of
    /// characters, long enough to be worth protecting.
    private static func looksLikeValue(_ candidate: String) -> Bool {
        guard candidate.count >= 6, !candidate.contains(" ") else { return false }
        // A bare number is an amount, an id, a year - not a secret.
        if candidate.allSatisfy(\.isNumber) { return false }
        return true
    }
}
