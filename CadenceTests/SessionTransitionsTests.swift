import XCTest
@testable import Cadence

/// One test per row of the transition table, each asserting the whole post-state
/// — including the fields the transition is supposed to clear.
final class SessionTransitionsTests: XCTestCase {

    // MARK: - start

    func testStartFromIdleReplacesThePlanAndBeginsARun() {
        let now = Clock.at(13, 48)
        let before = SessionState.idle(plannedDuration: 25 * minute, title: "Old plan")

        let after = SessionTransitions.start(
            before,
            duration: 45 * minute,
            title: "Draft the memo",
            linkedEventKey: "abc|1",
            now: now
        )

        XCTAssertEqual(after.status, .running)
        XCTAssertEqual(after.plannedDuration, 45 * minute)
        XCTAssertEqual(after.title, "Draft the memo")
        XCTAssertEqual(after.linkedEventKey, "abc|1")
        XCTAssertEqual(after.startedAt, now)
        XCTAssertEqual(after.endsAt, Clock.at(14, 33))
        XCTAssertEqual(after.segmentStartedAt, now)
        XCTAssertEqual(after.focusedBefore, 0)
        XCTAssertNil(after.remaining)
        XCTAssertNil(after.completedAt)
        assertInvariants(after)
    }

    func testStartWithoutATitleStoresNoName() {
        let now = Clock.at(13, 48)
        let before = SessionState.idle(title: "Standup", linkedEventKey: "abc|1")

        let after = SessionTransitions.start(before, duration: 25 * minute, now: now)

        XCTAssertNil(after.title, "a plain duration session stores no name")
        XCTAssertNil(after.linkedEventKey, "and no event provenance")
        assertInvariants(after)
    }

    func testStartAnotherFromCompleteClearsTheFinishedRun() {
        let before = SessionState.complete(
            plannedDuration: 25 * minute,
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            completedAt: Clock.at(14, 13),
            focusedBefore: 25 * minute
        )
        let now = Clock.at(14, 20)

        let after = SessionTransitions.startAnother(before, duration: 15 * minute, now: now)

        XCTAssertEqual(after.status, .running)
        XCTAssertEqual(after.plannedDuration, 15 * minute)
        XCTAssertNil(after.title, "a full plan replacement drops the old name")
        XCTAssertEqual(after.startedAt, now, "the new run starts its own span")
        XCTAssertEqual(after.endsAt, Clock.at(14, 35))
        XCTAssertEqual(after.segmentStartedAt, now)
        XCTAssertEqual(after.focusedBefore, 0, "focus accounting restarts")
        XCTAssertNil(after.completedAt)
        XCTAssertNil(after.remaining)
        assertInvariants(after)
    }

    // MARK: - pause / resume

    func testPauseFreezesRemainingAndBanksTheSegment() {
        let before = SessionState.running(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            segmentStartedAt: Clock.at(13, 48)
        )

        let after = SessionTransitions.pause(before, now: Clock.at(14, 0))

        XCTAssertEqual(after.status, .paused)
        XCTAssertEqual(after.remaining, 13 * minute)
        XCTAssertEqual(after.focusedBefore, 12 * minute)
        XCTAssertNil(after.endsAt, "pause clears the deadline")
        XCTAssertNil(after.segmentStartedAt, "and closes the segment")
        XCTAssertEqual(after.startedAt, Clock.at(13, 48), "the span keeps its start")
        XCTAssertEqual(after.plannedDuration, 25 * minute)
        XCTAssertEqual(after.title, "Draft the memo")
        XCTAssertNil(after.completedAt)
        assertInvariants(after)
    }

    func testResumeMaterialisesAFreshDeadlineFromTheRemainder() {
        let before = SessionState.paused(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            remaining: 13 * minute,
            focusedBefore: 12 * minute
        )
        let now = Clock.at(14, 5)

        let after = SessionTransitions.resume(before, now: now)

        XCTAssertEqual(after.status, .running)
        XCTAssertEqual(after.endsAt, Clock.at(14, 18), "the pause costs the session nothing")
        XCTAssertEqual(after.segmentStartedAt, now)
        XCTAssertNil(after.remaining, "resume clears the frozen remainder")
        XCTAssertEqual(after.focusedBefore, 12 * minute, "banked focus is untouched")
        XCTAssertEqual(after.startedAt, Clock.at(13, 48))
        XCTAssertEqual(after.plannedDuration, 25 * minute)
        XCTAssertEqual(after.title, "Draft the memo")
        XCTAssertNil(after.completedAt)
        assertInvariants(after)
    }

    func testFocusAccumulatesAcrossSuccessivePauses() {
        var state = SessionTransitions.start(
            SessionState.idle(),
            duration: 25 * minute,
            now: Clock.at(13, 48)
        )

        state = SessionTransitions.pause(state, now: Clock.at(13, 58))
        XCTAssertEqual(state.focusedBefore, 10 * minute)

        state = SessionTransitions.resume(state, now: Clock.at(14, 3))
        state = SessionTransitions.pause(state, now: Clock.at(14, 10))

        XCTAssertEqual(state.focusedBefore, 17 * minute, "the sum of the finished segments, not the last one")
        XCTAssertEqual(state.remaining, 8 * minute)
        assertInvariants(state)
    }

    // MARK: - reset

    func testResetFromRunningKeepsThePlanAndClearsTheRun() {
        let before = SessionState.running(
            plannedDuration: 45 * minute,
            title: "Draft the memo",
            linkedEventKey: "abc|1",
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 33),
            segmentStartedAt: Clock.at(13, 48)
        )

        let after = SessionTransitions.reset(before, now: Clock.at(14, 0))

        XCTAssertEqual(after.status, .idle)
        XCTAssertEqual(after.plannedDuration, 45 * minute, "the clock goes back to full")
        XCTAssertEqual(after.title, "Draft the memo", "the stored title survives reset")
        XCTAssertEqual(after.linkedEventKey, "abc|1")
        XCTAssertNil(after.startedAt)
        XCTAssertNil(after.endsAt)
        XCTAssertNil(after.remaining)
        XCTAssertNil(after.completedAt)
        XCTAssertNil(after.segmentStartedAt)
        XCTAssertEqual(after.focusedBefore, 0)
        assertInvariants(after)
    }

    func testResetFromPausedClearsTheFrozenRemainder() {
        let before = SessionState.paused(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            remaining: 13 * minute,
            focusedBefore: 12 * minute
        )

        let after = SessionTransitions.reset(before, now: Clock.at(14, 5))

        XCTAssertEqual(after.status, .idle)
        XCTAssertEqual(after.plannedDuration, 25 * minute)
        XCTAssertEqual(after.title, "Draft the memo")
        XCTAssertNil(after.remaining)
        XCTAssertNil(after.startedAt)
        XCTAssertEqual(after.focusedBefore, 0)
        assertInvariants(after)
    }

    func testResetFromCompleteClearsTheCompletion() {
        let before = SessionState.complete(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            completedAt: Clock.at(14, 13),
            focusedBefore: 25 * minute
        )

        let after = SessionTransitions.reset(before, now: Clock.at(14, 20))

        XCTAssertEqual(after.status, .idle)
        XCTAssertNil(after.completedAt)
        XCTAssertNil(after.startedAt)
        XCTAssertEqual(after.focusedBefore, 0)
        XCTAssertEqual(after.plannedDuration, 25 * minute)
        XCTAssertEqual(after.title, "Draft the memo")
        assertInvariants(after)
    }

    // MARK: - complete

    func testCompleteRecordsTheDeadlineRatherThanTheMomentItWasNoticed() {
        let before = SessionState.running(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            focusedBefore: 12 * minute,
            segmentStartedAt: Clock.at(14, 5)
        )

        let after = SessionTransitions.complete(before, now: Clock.at(14, 13))

        XCTAssertEqual(after.status, .complete)
        XCTAssertEqual(after.completedAt, Clock.at(14, 13))
        XCTAssertEqual(after.focusedBefore, 20 * minute)
        XCTAssertNil(after.endsAt, "complete clears the deadline")
        XCTAssertNil(after.segmentStartedAt, "and closes the segment")
        XCTAssertNil(after.remaining)
        XCTAssertEqual(after.startedAt, Clock.at(13, 48))
        XCTAssertEqual(after.plannedDuration, 25 * minute)
        XCTAssertEqual(after.title, "Draft the memo")
        assertInvariants(after)
    }

    // MARK: - extend

    func testExtendImmediatelyAfterCompletionRunsFromTheDeadline() {
        let before = SessionState.complete(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            completedAt: Clock.at(14, 13),
            focusedBefore: 25 * minute
        )
        let now = Clock.at(14, 13)

        let after = SessionTransitions.extend(before, now: now)

        XCTAssertEqual(after.status, .running)
        XCTAssertEqual(after.endsAt, Clock.at(14, 18))
        XCTAssertEqual(after.plannedDuration, 30 * minute, "the plan grows with the extension")
        XCTAssertEqual(after.segmentStartedAt, now)
        XCTAssertNil(after.completedAt, "extend clears the completion")
        XCTAssertNil(after.remaining)
        XCTAssertEqual(after.startedAt, Clock.at(13, 48), "the span keeps its original start")
        XCTAssertEqual(after.title, "Draft the memo", "extend keeps the title")
        XCTAssertEqual(after.focusedBefore, 25 * minute)
        assertInvariants(after)
    }

    func testExtendLongAfterCompletionBuysFiveMinutesFromNow() {
        let before = SessionState.complete(
            startedAt: Clock.at(13, 48),
            completedAt: Clock.at(14, 13),
            focusedBefore: 25 * minute
        )
        let now = Clock.at(14, 23)

        let after = SessionTransitions.extend(before, now: now)

        XCTAssertEqual(after.endsAt, Clock.at(14, 28), "not a deadline already in the past")
        XCTAssertEqual(after.segmentStartedAt, now, "the ten idle minutes earn no focus")
        assertInvariants(after)
    }

    // MARK: - duration selection

    func testSelectDurationInIdleRescopesThePlan() {
        let before = SessionState.idle(plannedDuration: 25 * minute, title: "Draft the memo")

        let after = SessionTransitions.selectDuration(before, duration: 45 * minute, now: Clock.at(13, 48))

        XCTAssertEqual(after.plannedDuration, 45 * minute)
        XCTAssertEqual(after.status, .idle)
        XCTAssertEqual(after.title, "Draft the memo")
        assertInvariants(after)
    }
}
