import XCTest
@testable import Cadence

final class DerivedValuesTests: XCTestCase {

    // MARK: - effectiveStatus

    func testEffectiveStatusFoldsInAnElapsedDeadlineAndNothingElse() {
        let now = Clock.at(14, 0)

        XCTAssertEqual(SessionState.idle().effectiveStatus(now), .idle)
        XCTAssertEqual(
            SessionState.paused(startedAt: Clock.at(13, 48), remaining: 13 * minute, focusedBefore: 12 * minute)
                .effectiveStatus(now),
            .paused
        )
        XCTAssertEqual(
            SessionState.complete(startedAt: Clock.at(13, 48), completedAt: Clock.at(13, 55), focusedBefore: 7 * minute)
                .effectiveStatus(now),
            .complete
        )

        let running = SessionState.running(
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            segmentStartedAt: Clock.at(13, 48)
        )
        XCTAssertEqual(running.effectiveStatus(now), .running)
        XCTAssertEqual(running.effectiveStatus(Clock.at(14, 13)), .complete, "at the deadline, not after it")
        XCTAssertEqual(running.effectiveStatus(Clock.at(14, 14)), .complete)
    }

    // MARK: - remaining and progress

    func testRemainingComesFromTheDeadlineThePlanOrTheFrozenRemainder() {
        XCTAssertEqual(SessionState.idle(plannedDuration: 45 * minute).remaining(Clock.at(14, 0)), 45 * minute)
        XCTAssertEqual(
            SessionState.running(
                startedAt: Clock.at(13, 48),
                endsAt: Clock.at(14, 13),
                segmentStartedAt: Clock.at(13, 48)
            ).remaining(Clock.at(14, 0)),
            13 * minute
        )
        XCTAssertEqual(
            SessionState.paused(startedAt: Clock.at(13, 48), remaining: 13 * minute, focusedBefore: 12 * minute)
                .remaining(Clock.at(14, 5)),
            13 * minute,
            "frozen: time spent paused does not move it"
        )
        XCTAssertEqual(
            SessionState.complete(startedAt: Clock.at(13, 48), completedAt: Clock.at(14, 13), focusedBefore: 25 * minute)
                .remaining(Clock.at(14, 20)),
            0
        )
    }

    func testProgressIsClampedAndFreezesWhilePaused() {
        let running = SessionState.running(
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            segmentStartedAt: Clock.at(13, 48)
        )
        XCTAssertEqual(running.progress(Clock.at(13, 48)), 0, accuracy: 0.0001)
        XCTAssertEqual(running.progress(Clock.at(14, 0)), 12.0 / 25.0, accuracy: 0.0001)
        XCTAssertEqual(running.progress(Clock.at(15, 0)), 1, "clamped past the deadline")

        let paused = SessionState.paused(
            startedAt: Clock.at(13, 48),
            remaining: 13 * minute,
            focusedBefore: 12 * minute
        )
        XCTAssertEqual(paused.progress(Clock.at(14, 0)), 12.0 / 25.0, accuracy: 0.0001)
        XCTAssertEqual(paused.progress(Clock.at(14, 30)), 12.0 / 25.0, accuracy: 0.0001)
    }

    // MARK: - focus accounting

    func testFocusedIsCappedAtThePlan() {
        let running = SessionState.running(
            plannedDuration: 25 * minute,
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            segmentStartedAt: Clock.at(13, 48)
        )
        XCTAssertEqual(running.focused(Clock.at(14, 0)), 12 * minute)
        XCTAssertEqual(running.focused(Clock.at(15, 0)), 25 * minute, "never more focus than was asked for")
    }

    /// The worked example: a session started 1:48, paused five minutes, finishing
    /// 2:18 reports a 1:48–2:18 span and 25 min focused.
    func testPausedSessionReportsTheFullSpanAndOnlyTheTimeFocused() {
        let start = Clock.at(13, 48)
        var state = SessionTransitions.start(SessionState.idle(), duration: 25 * minute, now: start)

        state = SessionTransitions.pause(state, now: Clock.at(14, 0))
        state = SessionTransitions.resume(state, now: Clock.at(14, 5))
        XCTAssertEqual(state.endsAt, Clock.at(14, 18), "the five paused minutes push the deadline out")

        let finish = Clock.at(14, 18)
        state = SessionTransitions.complete(state, now: finish)

        XCTAssertEqual(state.span, start...finish)
        XCTAssertEqual(normalizingSpaces(state.spanText(locale: Clock.locale, timeZone: Clock.timeZone)), "1:48–2:18 PM")
        XCTAssertEqual(state.focused(finish), 25 * minute)
        XCTAssertEqual(
            normalizingSpaces(state.summaryLine(finish, locale: Clock.locale, timeZone: Clock.timeZone)),
            "1:48–2:18 PM · 25 min focused"
        )
    }

    func testSpanPrintsBothDayPeriodsWhenItCrossesNoon() {
        let state = SessionState.complete(
            plannedDuration: 45 * minute,
            startedAt: Clock.at(11, 45),
            completedAt: Clock.at(12, 30),
            focusedBefore: 45 * minute
        )
        XCTAssertEqual(normalizingSpaces(state.spanText(locale: Clock.locale, timeZone: Clock.timeZone)), "11:45 AM–12:30 PM")
    }

    func testSpanIsUnavailableUntilTheSessionHasFinished() {
        XCTAssertNil(SessionState.idle().span)
        XCTAssertNil(
            SessionState.running(
                startedAt: Clock.at(13, 48),
                endsAt: Clock.at(14, 13),
                segmentStartedAt: Clock.at(13, 48)
            ).span
        )
        XCTAssertNil(SessionState.idle().summaryLine(Clock.at(14, 0)))
    }

    // MARK: - displayName

    func testDisplayNameFallsBackToTheDurationWithoutStoringIt() {
        var state = SessionState.idle(plannedDuration: 25 * minute)
        XCTAssertEqual(state.displayName, "25 minute session")
        XCTAssertNil(state.title, "the fallback is presentation, never data")

        state.plannedDuration = 45 * minute
        XCTAssertEqual(state.displayName, "45 minute session")

        state.title = "Draft the memo"
        XCTAssertEqual(state.displayName, "Draft the memo")
    }

    // MARK: - clockTargets

    func testClockTargetsAreTheNextTwoHalfHoursPastTheLead() {
        let targets = ClockTarget.next(
            after: Clock.at(14, 8),
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )

        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0].date, Clock.at(14, 30))
        XCTAssertEqual(targets[0].label, "To 2:30")
        XCTAssertEqual(targets[0].minutes, 22)
        XCTAssertEqual(targets[1].date, Clock.at(15, 0))
        XCTAssertEqual(targets[1].label, "To 3:00")
        XCTAssertEqual(targets[1].minutes, 52)
    }

    func testClockTargetsSkipABoundaryInsideTheLead() {
        let targets = ClockTarget.next(
            after: Clock.at(14, 27),
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )

        XCTAssertEqual(targets[0].date, Clock.at(15, 0), "2:30 is only three minutes away")
        XCTAssertEqual(targets[1].date, Clock.at(15, 30))
    }

    func testClockTargetsRollOverTheHour() {
        let targets = ClockTarget.next(
            after: Clock.at(14, 57),
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )

        XCTAssertEqual(targets[0].date, Clock.at(15, 30))
        XCTAssertEqual(targets[1].date, Clock.at(16, 0))
    }

    // MARK: - snapshot freshness

    func testSnapshotFreshnessIsADayComparison() {
        let today = Clock.at(14, 0)
        let snapshot = CalendarSnapshot(
            day: Clock.startOfDay(today),
            events: [],
            lastSyncedAt: today,
            access: .authorized
        )

        XCTAssertTrue(snapshot.isFresh(Clock.at(23, 59), calendar: Clock.calendar))
        XCTAssertFalse(
            snapshot.isFresh(Clock.on(day: 5, 0, 1), calendar: Clock.calendar),
            "never yesterday's meetings"
        )
    }

    func testOccurrenceKeyIsCompositeOverTheOccurrenceStart() {
        let first = EventOccurrence.makeID(eventIdentifier: "standup", startsAt: Clock.on(day: 4, 9, 30))
        let second = EventOccurrence.makeID(eventIdentifier: "standup", startsAt: Clock.on(day: 5, 9, 30))

        XCTAssertNotEqual(first, second, "recurring occurrences share an event identifier")
        XCTAssertTrue(first.hasPrefix("standup|"))
    }
}
