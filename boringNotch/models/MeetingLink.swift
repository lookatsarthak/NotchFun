//
//  MeetingLink.swift
//  NotchFun
//

import Foundation

/// Finds the video-call link in a calendar event, for the Join button.
///
/// Looks in the event's URL, then its location, then its notes, which is where Google,
/// Outlook and Zoom put them. Only links on the services below count, matched by host and
/// path, so a Join button never opens an agenda document or a random web page. Only
/// https links are returned, so Join never hands a custom scheme to the system.
enum MeetingLink {
    enum Service: String, CaseIterable, Sendable {
        case meet = "Google Meet"
        case zoom = "Zoom"
        case teams = "Teams"
        case webex = "Webex"
        case whereby = "Whereby"
        case jitsi = "Jitsi"
        case facetime = "FaceTime"
    }

    struct Match: Equatable, Sendable {
        let url: URL
        let service: Service
    }

    static func find(url: URL?, location: String?, notes: String?) -> Match? {
        if let url, let service = service(for: url) { return Match(url: url, service: service) }
        for text in [location, notes] {
            guard let text, !text.isEmpty else { continue }
            for link in links(in: text) {
                if let service = service(for: link) { return Match(url: link, service: service) }
            }
        }
        return nil
    }

    /// The service a link joins, or nil if it isn't a meeting link we recognise.
    static func service(for url: URL) -> Service? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        let segments = path.split(separator: "/").map(String.init)

        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

        if host == "meet.google.com" {
            // A meeting code like abc-defg-hij, not the landing page or /new.
            guard let code = segments.first, code.contains("-") || code == "lookup" else { return nil }
            return .meet
        }
        if on("zoom.us") || on("zoomgov.com") {
            let joinPaths = ["j", "my", "w", "s", "wc"]
            guard let first = segments.first, joinPaths.contains(first), segments.count >= 2 else { return nil }
            return .zoom
        }
        if host == "teams.microsoft.com" || host == "teams.live.com" || host == "teams.cloud.microsoft" {
            guard path.contains("/meetup-join/") || segments.first == "meet" else { return nil }
            return .teams
        }
        if on("webex.com") {
            guard path.contains("/meet/") || path.contains("/join/") || path.hasSuffix("j.php")
                || path.contains("/wbxmjs/joinservice/") else { return nil }
            return .webex
        }
        if host == "whereby.com" {
            // whereby.com/room-name; the site's own pages have more segments or known names.
            let sitePages: Set<String> = ["information", "user", "org", "pricing", "login", "signup", "blog"]
            guard segments.count == 1, let room = segments.first, !sitePages.contains(room) else { return nil }
            return .whereby
        }
        if host == "meet.jit.si" {
            guard segments.count == 1 else { return nil }
            return .jitsi
        }
        if host == "facetime.apple.com" {
            guard segments.first == "join" else { return nil }
            return .facetime
        }
        return nil
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Every link in a block of text, in order. Notes from Outlook wrap links in <…>, and
    /// the detector reads through that.
    private static func links(in text: String) -> [URL] {
        guard let detector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }
}
