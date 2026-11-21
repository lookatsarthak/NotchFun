//
//  MeetingLinkTests.swift
//  boringNotchTests
//

import Foundation
import Testing

@Suite("Meeting links for the Join button")
struct MeetingLinkTests {

    private func service(_ string: String) -> MeetingLink.Service? {
        MeetingLink.service(for: URL(string: string)!)
    }

    @Test("Recognises each service's join links", arguments: [
        ("https://meet.google.com/abc-defg-hij", MeetingLink.Service.meet),
        ("https://us02web.zoom.us/j/81234567890?pwd=abc", .zoom),
        ("https://zoom.us/my/someroom", .zoom),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=x", .teams),
        ("https://teams.live.com/meet/9381234567", .teams),
        ("https://acme.webex.com/meet/jdoe", .webex),
        ("https://acme.webex.com/acme/j.php?MTID=m123", .webex),
        ("https://whereby.com/team-standup", .whereby),
        ("https://meet.jit.si/OurWeeklySync", .jitsi),
        ("https://facetime.apple.com/join#v=1&p=abc", .facetime),
    ])
    func recognises(_ link: String, _ expected: MeetingLink.Service) {
        #expect(service(link) == expected)
    }

    @Test("Ignores pages on the same sites that aren't meetings", arguments: [
        "https://meet.google.com/",
        "https://meet.google.com/new",
        "https://zoom.us/pricing",
        "https://zoom.us/j",
        "https://teams.microsoft.com/v2/",
        "https://www.webex.com/pricing/index.html",
        "https://whereby.com/information/about",
        "https://whereby.com/pricing",
        "https://docs.google.com/document/d/abc",
        "https://calendar.google.com/calendar/event?eid=abc",
        "http://meet.google.com/abc-defg-hij",
        "https://evilzoom.us/j/123",
    ])
    func ignores(_ link: String) {
        #expect(service(link) == nil)
    }

    @Test("The event URL wins, then the location, then the notes")
    func order() {
        let zoom = URL(string: "https://zoom.us/j/111")!
        let found = MeetingLink.find(url: zoom, location: "https://meet.google.com/aaa-bbbb-ccc", notes: nil)
        #expect(found?.service == .zoom)

        let fromLocation = MeetingLink.find(url: URL(string: "https://example.com/agenda"),
                                            location: "Room 4 / https://meet.google.com/aaa-bbbb-ccc",
                                            notes: "https://zoom.us/j/222")
        #expect(fromLocation?.service == .meet)
    }

    @Test("Finds the link inside Outlook-style notes")
    func notes() {
        let notes = """
        ________________________________________________________________________________
        Microsoft Teams meeting
        Join on your computer, mobile app or room device
        Click here to join the meeting<https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d>
        Meeting ID: 123 456 789
        Learn more<https://aka.ms/JoinTeamsMeeting>
        """
        let found = MeetingLink.find(url: nil, location: "Microsoft Teams Meeting", notes: notes)
        #expect(found?.service == .teams)
        #expect(found?.url.host == "teams.microsoft.com")
    }

    @Test("Notes with only other links give no Join button")
    func noMeeting() {
        #expect(MeetingLink.find(url: nil, location: "Café", notes: "Agenda: https://docs.google.com/doc/abc") == nil)
        #expect(MeetingLink.find(url: nil, location: nil, notes: nil) == nil)
    }
}
