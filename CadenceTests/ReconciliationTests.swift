import XCTest
@testable import Cadence

/// Nothing has to be awake for a session to finish. These are the cases where the
/// deadline passes with no process there to notice.
final class ReconciliationTests: XCTestCase {

    private func session(endingAt endsAt: Date) -> SessionState {
        .running(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            endsAt: endsAt,
            segmentStartedAt: Clock.at(13, 48)
        )
    }

    func testDeadlineElapsedWhileQuitReadsAsComplete() {
        let state = session(endingAt: Clock.at(14, 13))
        let relaunch = Clock.at(16, 30)

        XCTAssertEqual(state.effectiveStatus(relaunch), .complete, "derived without any transition")
        XCTAssertEqual(state.remaining(relaunch), 0)
        XCTAssertEqual(state.progress(relaunch), 1)

        let reconciled = SessionTransitions.reconciled(state, now: relaunch)
        XCTAssertEqual(reconciled.status, .complete)
        XCTAssertEqual(reconciled.completedAt, Clock.at(14, 13), "it finished when it said it would")
        XCTAssertEqual(reconciled.focusedBefore, 25 * minute, "not the two hours the app was quit")
        assertInvariants(reconciled)
    }

    func testMachineAsleepAcrossTheDeadlineBanksOnlyThePlannedTime() {
        // Asleep from 14:00; the deadline passes at 14:13; wake at 15:00.
        let state = session(endingAt: Clock.at(14, 13))
        let wake = Clock.at(15, 0)

        let reconciled = SessionTransitions.reconciled(state, now: wake)

        XCTAssertEqual(reconciled.status, .complete)
        XCTAssertEqual(reconciled.completedAt, Clock.at(14, 13))
        XCTAssertEqual(reconciled.focused(wake), 25 * minute)
        assertInvariants(reconciled)
    }

    func testATransitionRequestedAfterTheDeadlineIsJudgedAgainstTheCompletedState() {
        let state = session(endingAt: Clock.at(14, 13))
        let late = Clock.at(14, 30)

        // A stale widget asks to pause a session that has already finished.
        let after = SessionTransitions.pause(state, now: late)

        XCTAssertEqual(after.status, .complete, "reconciled first, then the pause guard rejects")
        XCTAssertEqual(after.completedAt, Clock.at(14, 13))
        assertInvariants(after)
    }

    func testExtendRequestedAfterAnUnnoticedDeadlineStillWorks() {
        let state = session(endingAt: Clock.at(14, 13))
        let late = Clock.at(14, 30)

        let after = SessionTransitions.extend(state, now: late)

        XCTAssertEqual(after.status, .running, "reconciliation makes extend legal")
        XCTAssertEqual(after.endsAt, Clock.at(14, 35))
        XCTAssertEqual(after.plannedDuration, 30 * minute)
        assertInvariants(after)
    }

    func testWallClockMovedBackwardsNeitherCompletesNorUnbanksFocus() {
        let state = SessionState.running(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            focusedBefore: 12 * minute,
            segmentStartedAt: Clock.at(14, 5)
        )
        // The clock jumps back behind the current segment's start.
        let backwards = Clock.at(13, 30)

        XCTAssertEqual(state.effectiveStatus(backwards), .running)
        XCTAssertEqual(state.remaining(backwards), 43 * minute, "derived from the deadline, not a counter")
        XCTAssertEqual(state.focused(backwards), 12 * minute, "the banked segment is not clawed back")
        XCTAssertEqual(state.progress(backwards), 0, "clamped rather than negative")

        let paused = SessionTransitions.pause(state, now: backwards)
        XCTAssertEqual(paused.focusedBefore, 12 * minute, "a backwards jump earns no negative focus")
        XCTAssertEqual(paused.remaining, 43 * minute)
        assertInvariants(paused)
    }

    func testPlannedDurationExhaustedByExtend() {
        // A finished session has focused exactly its plan; extending must grow the
        // budget, or the cap would swallow the extra time.
        let complete = SessionState.complete(
            plannedDuration: 25 * minute,
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            completedAt: Clock.at(14, 13),
            focusedBefore: 25 * minute
        )
        XCTAssertEqual(complete.focused(Clock.at(14, 13)), complete.plannedDuration)

        let extended = SessionTransitions.extend(complete, now: Clock.at(14, 13))
        XCTAssertEqual(extended.plannedDuration, 30 * minute)
        XCTAssertEqual(extended.remaining(Clock.at(14, 13)), 5 * minute)
        XCTAssertEqual(extended.progress(Clock.at(14, 13)), 25.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(extended.focused(Clock.at(14, 15)), 27 * minute, "the extension accrues focus")

        let finished = SessionTransitions.complete(extended, now: Clock.at(14, 18))
        XCTAssertEqual(finished.focusedBefore, 30 * minute)
        XCTAssertEqual(finished.focused(Clock.at(14, 18)), 30 * minute, "capped at the grown plan")
        XCTAssertEqual(finished.completedAt, Clock.at(14, 18))
        assertInvariants(finished)
    }
}
