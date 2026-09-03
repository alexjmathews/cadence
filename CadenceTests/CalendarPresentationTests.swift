import SwiftUI
import XCTest
@testable import Cadence

/// What the strip, the day list and the dropdown row say — the four strip states, the
/// buffer clause, and the two labels that carry a time.
final class CalendarPresentationTests: XCTestCase {

    private let now = Clock.at(14, 13)

    private func occurrence(
        _ identifier: String,
        _ title: String,
        at startsAt: Date,
        colorHex: String? = nil
    ) -> EventOccurrence {
        EventOccurrence(
            id: EventOccurrence.makeID(eventIdentifier: identifier, startsAt: startsAt),
            title: title,
            startsAt: startsAt,
            endsAt: startsAt.addingTimeInterval(30 * minute),
            colorHex: colorHex
        )
    }

    private func snapshot(_ events: [EventOccurrence]) -> CalendarSnapshot {
        CalendarSnapshot(
            day: Clock.startOfDay(now),
            events: events,
            lastSyncedAt: Clock.at(14, 13),
            access: .authorized
        )
    }

    private func strip(
        _ snapshot: CalendarSnapshot?,
        access: CalendarAccess = .authorized,
        dismissed: Set<String> = [],
        state: SessionState = .idle(),
        buffer: TimeInterval = 2 * minute
    ) -> StripContent {
        CalendarPresentation.strip(
            snapshot: snapshot,
            access: access,
            dismissed: dismissed,
            state: state,
            buffer: buffer,
            now: now,
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )
    }

    // MARK: - The four strip states

    func testAnUndecidedCalendarOffersTheConnectAffordance() {
        XCTAssertEqual(strip(nil, access: .notDetermined), .connect)
    }

    /// "Revoking calendar access degrades to the empty state rather than showing stale
    /// events" — even with a snapshot still in hand, denied shows no event.
    func testRevokedAccessShowsNoEventsEvenWithASnapshotInHand() {
        let held = snapshot([occurrence("review", "Review", at: Clock.at(15, 30))])

        XCTAssertEqual(strip(held, access: .denied), .denied)
        XCTAssertNil(strip(held, access: .denied).row)
    }

    /// §3.3: the strip says "nothing *else*" because it reaches this state both when
    /// the day is empty and when everything left has been dismissed.
    func testAnEmptyDayAndAFullyDismissedDayReadTheSame() {
        let review = occurrence("review", "Review", at: Clock.at(15, 30))

        XCTAssertEqual(strip(snapshot([])), .empty)
        XCTAssertEqual(strip(snapshot([review]), dismissed: [review.id]), .empty)
        XCTAssertEqual(strip(nil), .empty)
    }

    // MARK: - The event row

    func testTheEventRowCarriesTheTimeTheLeadAndTheBuffer() throws {
        let review = occurrence("review", "Design review — Q3 brief", at: Clock.at(15, 30))

        let row = try XCTUnwrap(strip(snapshot([review])).row)

        XCTAssertEqual(row.title, "Design review — Q3 brief")
        XCTAssertEqual(
            normalizingSpaces(row.metaText),
            "3:30 PM · in 77 min · ends 2 min early"
        )
        XCTAssertEqual(row.actionText, "Timer until 3:30")
        XCTAssertFalse(row.isDismissed)
    }

    /// "ends 0 min early" is not a thing to promise, so the clause goes with the buffer.
    func testTheBufferClauseIsAbsentWhenTheBufferIsOff() {
        let review = occurrence("review", "Review", at: Clock.at(15, 30))

        XCTAssertEqual(
            normalizingSpaces(strip(snapshot([review]), buffer: 0).row?.metaText),
            "3:30 PM · in 77 min"
        )
    }

    /// The mockup's `--running-meeting-session` strip keeps the event and drops the
    /// action: a second timer is unstartable (§5), so the button would be a lie.
    func testARunningSessionKeepsTheEventAndLosesTheAction() throws {
        let running = SessionState.running(
            startedAt: Clock.at(14, 2),
            endsAt: Clock.at(14, 27),
            segmentStartedAt: Clock.at(14, 2)
        )
        let review = occurrence("review", "Review", at: Clock.at(15, 30))

        let row = try XCTUnwrap(strip(snapshot([review]), state: running).row)

        XCTAssertEqual(row.title, "Review")
        XCTAssertNil(row.actionText)
        XCTAssertNil(row.listActionText)
    }

    /// Calendar rows inherit the source calendar's own colour (§1.2).
    func testTheRowTakesItsSourceCalendarColour() throws {
        let purple = occurrence("climbing", "Climbing", at: Clock.at(18, 30), colorHex: "A184C8")
        let none = occurrence("review", "Review", at: Clock.at(15, 30), colorHex: nil)

        XCTAssertEqual(EventRow.barColor(for: purple), Color(hexString: "A184C8"))
        XCTAssertEqual(EventRow.barColor(for: none), DesignTokens.Accent.event)
        XCTAssertNil(Color(hexString: "not-a-colour"))
    }

    // MARK: - Day list

    func testTheDayListKeepsDismissedRowsAndCountsThem() throws {
        let review = occurrence("review", "Review", at: Clock.at(15, 30))
        let oneToOne = occurrence("oneToOne", "One to one", at: Clock.at(16, 15))

        let list = CalendarPresentation.dayList(
            snapshot: snapshot([review, oneToOne]),
            dismissed: [review.id],
            state: .idle(),
            buffer: 2 * minute,
            now: now,
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )

        XCTAssertEqual(list.headerText, "TODAY · WEDNESDAY")
        XCTAssertEqual(normalizingSpaces(list.syncedText), "synced 2:13 PM")
        XCTAssertEqual(list.footerText, "2 events today · 1 hidden")
        XCTAssertEqual(list.rows.count, 2, "a dismissed row stays, because it is where the undo is")
        XCTAssertTrue(list.rows[0].isDismissed)
        XCTAssertNil(list.rows[0].listActionText, "a dismissed row offers undo, not a start")
        XCTAssertEqual(list.rows[1].listActionText, "Start 120m")
        XCTAssertEqual(normalizingSpaces(list.rows[1].timeText), "4:15 PM")
    }

    func testTheDayListFooterCounts() {
        XCTAssertEqual(CalendarPresentation.footerText(events: 0, hidden: 0), "0 events today")
        XCTAssertEqual(CalendarPresentation.footerText(events: 1, hidden: 0), "1 event today")
        XCTAssertEqual(CalendarPresentation.footerText(events: 4, hidden: 1), "4 events today · 1 hidden")
    }

    func testADayListWithoutASnapshotHasNoSyncTime() {
        let list = CalendarPresentation.dayList(
            snapshot: nil,
            dismissed: [],
            state: .idle(),
            buffer: 2 * minute,
            now: now,
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )

        XCTAssertNil(list.syncedText)
        XCTAssertTrue(list.rows.isEmpty)
        XCTAssertEqual(list.footerText, "0 events today")
    }

    // MARK: - Dropdown row

    /// D7: a clock target means what its label says, but the meeting row *does* carry
    /// the buffer — walking in late is the thing being avoided.
    func testTheDropdownMeetingRowCarriesTheBuffer() throws {
        let review = occurrence("review", "Design review", at: Clock.at(15, 30))

        let preset = try XCTUnwrap(
            CalendarPresentation.meetingPreset(for: review, buffer: 2 * minute, now: now)
        )

        XCTAssertEqual(preset.title, "To Design review")
        XCTAssertEqual(preset.duration, 75 * minute)
        XCTAssertEqual(preset.minutes, 75)
    }

    func testThereIsNoDropdownRowWithoutASuggestion() {
        XCTAssertNil(CalendarPresentation.meetingPreset(for: nil, buffer: 2 * minute, now: now))
        XCTAssertNil(
            CalendarPresentation.meetingPreset(
                for: occurrence("soon", "Soon", at: Clock.at(14, 14)),
                buffer: 2 * minute,
                now: now
            )
        )
    }

    /// §3.3 gives the dropdown a *fact about the day*, so it may only be stated when
    /// there is a day to state it about. Behind an unopened or closed gate the row is
    /// about access — and it is the one connect affordance a user who never opens the
    /// window will ever see.
    func testTheDropdownRowIsAboutAccessBeforeItIsAboutTheDay() {
        let review = occurrence("review", "Design review", at: Clock.at(15, 30))

        XCTAssertEqual(
            dropdown(access: .notDetermined, suggestion: review),
            .connect
        )
        XCTAssertEqual(
            dropdown(access: .denied, suggestion: nil),
            .denied
        )
        XCTAssertEqual(
            dropdown(access: .authorized, suggestion: nil),
            .empty
        )
        XCTAssertEqual(
            dropdown(access: .authorized, suggestion: review).preset?.title,
            "To Design review"
        )
    }

    /// The regression: `Nothing on your calendar today` was said on the single
    /// condition "no suggestion", so the dropdown asserted it while the window's strip
    /// was correctly offering `Connect` — and the dropdown carried no way to grant
    /// access at all.
    func testOnlyAnAuthorizedAndEmptyDayGetsTheEmptyCopy() {
        XCTAssertEqual(
            dropdown(access: .authorized, suggestion: nil).copy,
            "Nothing on your calendar today"
        )
        XCTAssertNotEqual(
            dropdown(access: .notDetermined, suggestion: nil).copy,
            "Nothing on your calendar today"
        )
        XCTAssertNotEqual(
            dropdown(access: .denied, suggestion: nil).copy,
            "Nothing on your calendar today"
        )
        XCTAssertEqual(dropdown(access: .notDetermined, suggestion: nil).copy, "Connect your calendar")
        XCTAssertEqual(dropdown(access: .denied, suggestion: nil).copy, "Calendar access is off")
        // A meeting row is a preset, not copy.
        XCTAssertNil(
            dropdown(
                access: .authorized,
                suggestion: occurrence("review", "Design review", at: Clock.at(15, 30))
            ).copy
        )
    }

    /// An authorized day whose events have all been dismissed, or eaten by the buffer,
    /// still reaches the empty copy — the state the fix must not have taken away.
    func testAnAuthorizedDayWithNothingLeftKeepsTheEmptyCopy() {
        XCTAssertEqual(
            dropdown(
                access: .authorized,
                suggestion: occurrence("soon", "Soon", at: Clock.at(14, 14))
            ),
            .empty,
            "the buffer has eaten it, so there is no row to offer"
        )
    }

    private func dropdown(
        access: CalendarAccess,
        suggestion: EventOccurrence?,
        buffer: TimeInterval = 2 * minute
    ) -> DropdownCalendarContent {
        CalendarPresentation.dropdownCalendar(
            access: access,
            suggestion: suggestion,
            buffer: buffer,
            now: now
        )
    }

    // MARK: - Freshness at the read (§2.3, §4)

    /// The window can be open and frontmost across midnight with no calendar edit and
    /// no activation to refresh it. `TODAY · THURSDAY` over yesterday's rows, with
    /// `synced 11:47 PM` beside it, is the state §2.3 forbids: "false means show the
    /// empty state, never yesterday's meetings".
    func testADayListIgnoresASnapshotThatIsNotTodays() {
        let review = occurrence("review", "Review", at: Clock.at(15, 30))
        let tomorrow = Clock.on(day: 5, 0, 5)

        let list = CalendarPresentation.dayList(
            snapshot: snapshot([review]),
            dismissed: [],
            state: .idle(),
            buffer: 2 * minute,
            now: tomorrow,
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )

        XCTAssertTrue(list.rows.isEmpty, "yesterday's meetings are not today's list")
        XCTAssertNil(list.syncedText, "and there is no sync time to claim for a day with no snapshot")
        XCTAssertEqual(list.footerText, "0 events today")
        XCTAssertEqual(list.headerText, "TODAY · THURSDAY", "the header is the day, not the snapshot")
    }

    /// The strip escaped this only by luck — stale events are all in the past, so
    /// nothing was suggested. This is the guard rather than the accident.
    func testTheStripIgnoresASnapshotThatIsNotTodays() {
        let tomorrow = Clock.on(day: 5, 0, 5)
        // An event *later* than the rollover, so lead alone would still suggest it.
        let evening = occurrence("late", "Late", at: Clock.on(day: 5, 9, 0))

        let content = CalendarPresentation.strip(
            snapshot: snapshot([evening]),
            access: .authorized,
            dismissed: [],
            state: .idle(),
            buffer: 2 * minute,
            now: tomorrow,
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )

        XCTAssertEqual(content, .empty)
    }

    // MARK: - One threshold, two surfaces (§4)

    /// The regression: `startable` asked only for a positive duration, so the day list
    /// offered `Start 0m` for an event twenty seconds past the buffer — and pressing it
    /// started a twenty-second session — while the strip, gated by `suggestedEvent`,
    /// correctly offered nothing.
    func testTheDayListWillNotOfferASubMinuteSession() {
        // 2 m 20 s away with a 2 m buffer: 20 seconds of session, which rounds to 0m.
        let soon = occurrence("soon", "Soon", at: Clock.at(14, 15, 20))

        let list = CalendarPresentation.dayList(
            snapshot: snapshot([soon]),
            dismissed: [],
            state: .idle(),
            buffer: 2 * minute,
            now: now,
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )

        XCTAssertEqual(list.rows.count, 1, "the event is still a row; it is just not a start")
        XCTAssertNil(list.rows[0].listActionText)
        XCTAssertNil(list.rows[0].actionText)
        XCTAssertEqual(strip(snapshot([soon])), .empty, "and the strip agrees, as it always did")
    }

    /// Either side of §4's threshold, on the same event, for both surfaces at once.
    func testBothSurfacesShareTheOneThreshold() throws {
        // 3 m 1 s away less a 2 m buffer is 61 s: past the minimum lead.
        let justEnough = occurrence("ok", "Ok", at: Clock.at(14, 16, 1))
        // One second less is exactly the lead, and so not *past* it.
        let notEnough = occurrence("no", "No", at: Clock.at(14, 16))

        let offered = try XCTUnwrap(strip(snapshot([justEnough])).row)
        XCTAssertNotNil(offered.actionText)
        XCTAssertNotNil(offered.listActionText)

        XCTAssertEqual(strip(snapshot([notEnough])), .empty)
        let refused = CalendarPresentation.dayList(
            snapshot: snapshot([notEnough]),
            dismissed: [],
            state: .idle(),
            buffer: 2 * minute,
            now: now,
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )
        XCTAssertNil(refused.rows[0].listActionText)
    }
}
