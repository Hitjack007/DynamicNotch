import Testing
import Foundation
import AppKit
@testable import DynamicNotch

// MARK: - Helpers

private func calendar(isReminder: Bool = false) -> CalendarModel {
    CalendarModel(id: "cal", account: "acct", title: "Calendar", color: .systemBlue, isSubscribed: false, isReminder: isReminder)
}

private func event(
    id: String = "event-id",
    start: Date = Date(),
    end: Date = Date().addingTimeInterval(3600),
    type: EventType = .event(.unknown),
    participants: [Participant] = [],
    isAllDay: Bool = false,
    hasRecurrenceRules: Bool = false
) -> EventModel {
    EventModel(
        id: id, start: start, end: end, title: "Title", location: nil, notes: nil, url: nil,
        isAllDay: isAllDay, type: type, calendar: calendar(isReminder: type.isReminder),
        participants: participants, timeZone: nil, hasRecurrenceRules: hasRecurrenceRules, priority: nil
    )
}

// MARK: - AttendanceStatus

@Suite("AttendanceStatus ordering")
struct AttendanceStatusTests {

    @Test("accepted < maybe < declined < pending < unknown")
    func orderingMatchesComparisonValue() {
        let ordered: [AttendanceStatus] = [.accepted, .maybe, .declined, .pending, .unknown]
        #expect(ordered == ordered.sorted(), "declined sorts before pending, even though pending is declared first")
    }
}

// MARK: - EventType

@Suite("EventType flags")
struct EventTypeTests {

    @Test("isEvent/isBirthday/isReminder each identify exactly their own case")
    func typeFlags() {
        #expect(EventType.event(.accepted).isEvent)
        #expect(!EventType.event(.accepted).isBirthday)
        #expect(!EventType.event(.accepted).isReminder)

        #expect(EventType.birthday.isBirthday)
        #expect(!EventType.birthday.isEvent)

        #expect(EventType.reminder(completed: true).isReminder)
        #expect(!EventType.reminder(completed: true).isEvent)
    }
}

// MARK: - EventModel

@Suite("EventModel derived properties")
struct EventModelTests {

    @Test("attendance returns .unknown for anything that isn't an .event")
    func attendanceDefaultsToUnknownForNonEvents() {
        #expect(event(type: .event(.accepted)).attendance == .accepted)
        #expect(event(type: .birthday).attendance == .unknown)
        #expect(event(type: .reminder(completed: false)).attendance == .unknown)
    }

    @Test("isMeeting is true only when there's at least one participant")
    func isMeetingReflectsParticipants() {
        #expect(!event(participants: []).isMeeting)
        let participant = Participant(name: "Someone", status: .accepted, isOrganizer: false, isCurrentUser: false)
        #expect(event(participants: [participant]).isMeeting)
    }

    @Test("eventStatus classifies by comparing start/end against now")
    func eventStatusClassification() {
        let farFuture = Date().addingTimeInterval(1_000_000)
        let farPast = Date().addingTimeInterval(-1_000_000)

        #expect(event(start: farFuture, end: farFuture.addingTimeInterval(3600)).eventStatus == .upcoming)
        #expect(event(start: farPast, end: Date().addingTimeInterval(1_000_000)).eventStatus == .inProgress)
        #expect(event(start: farPast, end: farPast.addingTimeInterval(3600)).eventStatus == .ended)
    }

    @Test("calendarAppURL() routes reminders to the Reminders app URL scheme")
    func reminderURL() {
        let url = event(id: "abc123", type: .reminder(completed: false)).calendarAppURL()
        #expect(url?.absoluteString == "x-apple-reminderkit://remcdreminder/abc123")
    }

    @Test("calendarAppURL() for a non-repeating event has no embedded date component")
    func nonRepeatingEventURL() {
        let url = event(id: "abc123", type: .event(.accepted), hasRecurrenceRules: false).calendarAppURL()
        #expect(url?.absoluteString == "ical://ekevent/abc123?method=show&options=more")
    }

    @Test("calendarAppURL() for a repeating timed event embeds the UTC start date")
    func repeatingTimedEventURL() {
        let start = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z
        let url = event(id: "abc123", start: start, type: .event(.accepted), isAllDay: false, hasRecurrenceRules: true).calendarAppURL()
        #expect(url?.absoluteString == "ical://ekevent/2025-01-01T00:00:00+0000/abc123?method=show&options=more")
    }

    @Test("calendarAppURL() percent-encodes an id containing spaces")
    func idWithSpacesIsPercentEncoded() {
        let url = event(id: "an id", type: .event(.accepted)).calendarAppURL()
        #expect(url?.absoluteString.contains("an%20id") == true)
    }
}
