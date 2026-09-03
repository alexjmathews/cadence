import XCTest
@testable import Cadence

/// What the widget shows, asserted where it is decided. The stage's exit criteria are
/// claims about presentation — "suggestions are absent while running", "the pane falls
/// back to `displayName`", "empty-calendar copy instead of a blank suggestion row" —
/// and each one is a fact about these two functions.
final class WidgetPresentationTests: XCTestCase {

    private func tile(
        _ state: SessionState,
        suggestion: EventOccurrence? = nil,
        at now: Date
    ) -> WidgetTile {
        WidgetPresentation.tile(
            for: state,
            suggestion: suggestion,
            now: now,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )
    }

    private func pane(
        _ state: SessionState,
        snapshot: CalendarSnapshot? = nil,
        dismissed: Set<String> = [],
        buffer: TimeInterval = 120,
        at now: Date
    ) -> WidgetPane {
        var preferences = Preferences()
        preferences.endEarlyBuffer = buffer
        return WidgetPresentation.pane(
            for: state,
            snapshot: snapshot,
            dismissed: dismissed,
            preferences: preferences,
            now: now,
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )
    }

    private func event(
        id: String = "event|1",
        title: String = "Design review",
        at startsAt: Date,
        colorHex: String? = "FF8A3D"
    ) -> EventOccurrence {
        EventOccurrence(
            id: id,
            title: title,
            startsAt: startsAt,
            endsAt: startsAt.addingTimeInterval(30 * minute),
            colorHex: colorHex
        )
    }

    private func snapshot(_ events: [EventOccurrence], at now: Date) -> CalendarSnapshot {
        CalendarSnapshot(
            day: Clock.startOfDay(now),
            events: events,
            lastSyncedAt: now,
            access: .authorized
        )
    }

    // MARK: - Tile

    func testIdleTileNamesTheNextEventAndOffersTheStoredPlan() {
        let now = Clock.at(14, 12)
        let value = tile(
            .idle(plannedDuration: 25 * minute),
            suggestion: event(at: Clock.at(15, 30)),
            at: now
        )

        XCTAssertEqual(value.status, .idle)
        XCTAssertEqual(normalizingSpaces(value.statusText), "next 3:30 PM")
        XCTAssertEqual(value.countdown, .text("25:00"))
        XCTAssertEqual(value.progress, 0)
        XCTAssertEqual(value.caption, "Ready")
        XCTAssertEqual(value.primary.title, "Start 25 min")
        XCTAssertEqual(value.primary.action, .start)
        XCTAssertNil(value.secondary, "idle offers nothing but Start")
    }

    /// The reserved status row: nothing to say rather than an invented clock.
    func testIdleTileSaysNothingWithNoSuggestion() {
        let value = tile(.idle(), suggestion: nil, at: Clock.at(14, 12))
        XCTAssertNil(value.statusText)
    }

    /// P1: the running card hands SwiftUI a range and lets it count.
    func testRunningTileCountsItselfFromTheDeadline() {
        let now = Clock.at(14, 12, 28)
        let state = SessionState.running(
            title: "Design review",
            startedAt: Clock.at(14, 2),
            endsAt: Clock.at(14, 27),
            segmentStartedAt: Clock.at(14, 2)
        )
        let value = tile(state, at: now)

        XCTAssertEqual(value.status, .running)
        XCTAssertEqual(normalizingSpaces(value.statusText), "ends 2:27 PM")
        XCTAssertEqual(value.countdown, .interval(now...Clock.at(14, 27)))
        XCTAssertEqual(value.caption, "Design review")
        XCTAssertEqual(value.primary.action, .pause)
        XCTAssertEqual(value.secondary?.action, .reset)
        XCTAssertEqual(value.secondary?.isGlyph, true)
    }

    /// P5: the fallback is presentation and is the same string every surface uses.
    func testRunningTileFallsBackToTheDerivedName() {
        let value = tile(
            SessionState.running(
                plannedDuration: 25 * minute,
                startedAt: Clock.at(14, 2),
                endsAt: Clock.at(14, 27),
                segmentStartedAt: Clock.at(14, 2)
            ),
            at: Clock.at(14, 12)
        )
        XCTAssertEqual(value.caption, "25 minute session")
    }

    /// A paused session has no deadline to print (§2.1), so it does not print one.
    func testPausedTileFreezesTheClockAndNamesNoDeadline() {
        let value = tile(
            SessionState.paused(
                title: "Design review",
                startedAt: Clock.at(14, 2),
                remaining: 14 * minute + 32,
                focusedBefore: 10 * minute + 28
            ),
            at: Clock.at(14, 20)
        )

        XCTAssertEqual(value.statusText, "paused")
        XCTAssertEqual(value.countdown, .text("14:32"))
        XCTAssertEqual(value.primary.action, .resume)
        XCTAssertEqual(value.secondary?.action, .reset)
    }

    func testCompleteTileReportsTheFocusedTotalAndOffersBothEdges() {
        let value = tile(
            SessionState.complete(
                title: "Design review",
                startedAt: Clock.at(13, 48),
                completedAt: Clock.at(14, 13),
                focusedBefore: 25 * minute
            ),
            at: Clock.at(14, 20)
        )

        XCTAssertEqual(value.status, .complete)
        XCTAssertEqual(normalizingSpaces(value.statusText), "ended 2:13 PM")
        XCTAssertEqual(value.countdown, .text("00:00"))
        XCTAssertEqual(value.progress, 1)
        XCTAssertEqual(value.caption, "Complete · 25 min")
        XCTAssertEqual(value.primary.action, .start, "Start another is the start edge")
        XCTAssertEqual(value.secondary?.action, .extend)
    }

    /// D4: a deadline that passed while nothing was awake reads as complete, and the
    /// card is drawn from that rather than from the stored `running`.
    func testAnElapsedRunningSessionDrawsAsComplete() {
        let state = SessionState.running(
            startedAt: Clock.at(14, 2),
            endsAt: Clock.at(14, 27),
            segmentStartedAt: Clock.at(14, 2)
        )
        let value = tile(state, at: Clock.at(14, 40))

        XCTAssertEqual(value.status, .complete)
        XCTAssertEqual(value.countdown, .text("00:00"))
        XCTAssertEqual(value.primary.action, .start)
    }

    // MARK: - Pane

    func testTheIdlePaneOffersADurationAClockTargetAndTheMeeting() {
        let now = Clock.at(14, 12)
        let meeting = event(at: Clock.at(15, 30))

        guard case .suggestions(let rows) = pane(
            .idle(),
            snapshot: snapshot([meeting], at: now),
            at: now
        ) else { return XCTFail("idle shows suggestions") }

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].title, "45 minutes")
        XCTAssertEqual(rows[0].action, .startDuration(45 * minute))
        XCTAssertNil(rows[0].barColorHex, "a duration row inherits no calendar colour")

        XCTAssertEqual(rows[1].title, "To 2:30")
        XCTAssertEqual(rows[2].title, "Design review")
        XCTAssertEqual(rows[2].action, .startMeeting(eventKey: meeting.id))
        XCTAssertEqual(rows[2].barColorHex, "FF8A3D")
        // 2:12 to 3:30 less the 2 minute buffer.
        XCTAssertEqual(rows[2].metaText, "76m")
    }

    /// The stage's own bullet: copy, not a blank row — and copy is not a control.
    func testAnEmptyCalendarGetsCopyRatherThanABlankRow() {
        let now = Clock.at(14, 12)

        guard case .suggestions(let rows) = pane(
            .idle(),
            snapshot: snapshot([], at: now),
            at: now
        ) else { return XCTFail("idle shows suggestions") }

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[2].title, WidgetPresentation.emptyCalendarCopy)
        XCTAssertNil(rows[2].action, "copy is not a button")
        XCTAssertNil(rows[2].metaText)
    }

    /// No snapshot at all — the app has never synced, or access is off — reads the
    /// same way as an empty day. The widget cannot prompt, so there is nothing else
    /// honest to offer.
    func testNoSnapshotReadsAsAnEmptyCalendar() {
        let now = Clock.at(14, 12)

        guard case .suggestions(let rows) = pane(.idle(), snapshot: nil, at: now)
        else { return XCTFail("idle shows suggestions") }

        XCTAssertEqual(rows[2].title, WidgetPresentation.emptyCalendarCopy)
    }

    func testADismissedEventIsNotSuggested() {
        let now = Clock.at(14, 12)
        let first = event(id: "a|1", title: "First", at: Clock.at(15, 0))
        let second = event(id: "b|1", title: "Second", at: Clock.at(16, 0))

        guard case .suggestions(let rows) = pane(
            .idle(),
            snapshot: snapshot([first, second], at: now),
            dismissed: [first.id],
            at: now
        ) else { return XCTFail("idle shows suggestions") }

        XCTAssertEqual(rows[2].title, "Second", "dismissing promotes the next event")
    }

    /// The exit criterion, at the one place it is decided.
    func testSuggestionsAreAbsentWhileRunning() {
        let now = Clock.at(14, 12)
        let state = SessionState.running(
            title: "Design review",
            startedAt: Clock.at(14, 2),
            endsAt: Clock.at(14, 27),
            segmentStartedAt: Clock.at(14, 2)
        )

        guard case .session(let label, let title, let meta) = pane(
            state,
            snapshot: snapshot([event(at: Clock.at(15, 30))], at: now),
            at: now
        ) else { return XCTFail("a running session shows itself, not alternatives") }

        XCTAssertEqual(label, "In session")
        XCTAssertEqual(title, "Design review")
        XCTAssertEqual(normalizingSpaces(meta), "Started 2:02 PM")
    }

    func testSuggestionsAreAbsentWhilePausedAndWhileComplete() {
        let now = Clock.at(14, 20)
        let paused = SessionState.paused(
            startedAt: Clock.at(14, 2),
            remaining: 5 * minute,
            focusedBefore: 20 * minute
        )
        let complete = SessionState.complete(
            startedAt: Clock.at(13, 48),
            completedAt: Clock.at(14, 13),
            focusedBefore: 25 * minute
        )
        let day = snapshot([event(at: Clock.at(15, 30))], at: now)

        guard case .session(let pausedLabel, _, _) = pane(paused, snapshot: day, at: now),
              case .session(let completeLabel, let completeTitle, let completeMeta) =
                pane(complete, snapshot: day, at: now)
        else { return XCTFail("neither state offers alternatives") }

        XCTAssertEqual(pausedLabel, "In session")
        XCTAssertEqual(completeLabel, "Session complete")
        XCTAssertEqual(completeTitle, "25 minute session", "P5's fallback, in the pane")
        XCTAssertEqual(normalizingSpaces(completeMeta), "Started 1:48 PM")
    }

    // MARK: - Buffer

    /// §2.2 and P4: the widget's meeting row is priced against the *saved* buffer,
    /// which is why the same row is worth different lengths to different users.
    func testTheMeetingRowIsPricedAgainstTheSavedBuffer() {
        let now = Clock.at(14, 0)
        let day = snapshot([event(at: Clock.at(15, 0))], at: now)

        func meetingMinutes(buffer: TimeInterval) -> String? {
            guard case .suggestions(let rows) = pane(
                .idle(), snapshot: day, buffer: buffer, at: now
            ) else { return nil }
            return rows[2].metaText
        }

        XCTAssertEqual(meetingMinutes(buffer: 0), "60m")
        XCTAssertEqual(meetingMinutes(buffer: 120), "58m")
        XCTAssertEqual(meetingMinutes(buffer: 180), "57m")
    }

    /// §4's one threshold. An event the buffer has eaten is not offered at all, and
    /// the row becomes copy rather than `Start 0m`.
    func testAnEventTooCloseToTimeAgainstIsNotOffered() {
        let now = Clock.at(14, 0)
        let day = snapshot([event(at: Clock.at(14, 2, 30))], at: now)

        guard case .suggestions(let rows) = pane(.idle(), snapshot: day, at: now)
        else { return XCTFail("idle shows suggestions") }

        XCTAssertEqual(rows[2].title, WidgetPresentation.emptyCalendarCopy)
    }

    /// §2.3: never yesterday's meetings.
    func testAStaleSnapshotSuggestsNothing() {
        let now = Clock.at(14, 0)
        var yesterday = snapshot([event(at: Clock.at(15, 30))], at: now)
        yesterday.day = Clock.startOfDay(Clock.on(day: 3, 14, 0))

        guard case .suggestions(let rows) = pane(.idle(), snapshot: yesterday, at: now)
        else { return XCTFail("idle shows suggestions") }

        XCTAssertEqual(rows[2].title, WidgetPresentation.emptyCalendarCopy)
    }

    /// The card has room for three rows and the derivation offers three, whatever the
    /// day looks like — which is what keeps the pane from reflowing.
    func testThePaneAlwaysOffersExactlyThreeRows() {
        let now = Clock.at(14, 0)
        let busy = snapshot(
            (0..<6).map { event(id: "e|\($0)", title: "Event \($0)", at: Clock.at(15 + $0, 0)) },
            at: now
        )

        for day: CalendarSnapshot? in [busy, snapshot([], at: now), nil] {
            guard case .suggestions(let rows) = pane(.idle(), snapshot: day, at: now)
            else { return XCTFail("idle shows suggestions") }
            XCTAssertEqual(rows.count, DesignTokens.Layout.Widget.suggestionRowLimit)
        }
    }

    /// Three rows is a geometry commitment, so it has to hold at every hour of the day
    /// and not just at the mockups' 2 PM. The count is built from a fixed preset, a
    /// derived clock target and a conditional meeting row, and the last two both vary
    /// with the clock — a target the day has run out of, or a meeting the buffer has
    /// eaten, once left a two-row pane and reflowed the card.
    func testThePaneOffersThreeRowsAtEveryHourOfTheDay() {
        let limit = DesignTokens.Layout.Widget.suggestionRowLimit

        for hour in 0..<24 {
            for atMinute in [0, 5, 27, 29, 31, 55, 58] {
                let now = Clock.at(hour, atMinute)
                // A meeting far enough out to be offered, one too close for the
                // buffer to leave anything, and no calendar at all.
                let days: [CalendarSnapshot?] = [
                    snapshot([event(id: "e|far", title: "Far", at: now.addingTimeInterval(90 * minute))], at: now),
                    snapshot([event(id: "e|near", title: "Near", at: now.addingTimeInterval(30))], at: now),
                    snapshot([], at: now),
                    nil,
                ]

                for day in days {
                    guard case .suggestions(let rows) = pane(.idle(), snapshot: day, at: now)
                    else { return XCTFail("idle shows suggestions") }
                    XCTAssertEqual(
                        rows.count, limit,
                        "the pane reflowed at \(hour):\(atMinute)"
                    )
                    XCTAssertEqual(
                        Set(rows.map(\.id)).count, limit,
                        "every row needs its own identity at \(hour):\(atMinute)"
                    )
                }
            }
        }
    }
}
