import XCTest
@testable import Cadence

/// The "cannot accidentally" stories. Every guard is a no-op: a widget rendered
/// from a stale timeline can legitimately ask for an illegal transition, and the
/// answer is the state it already had.
final class SessionGuardTests: XCTestCase {
    private let now = Clock.at(14, 0)

    private var runningState: SessionState {
        .running(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            segmentStartedAt: Clock.at(13, 48)
        )
    }

    private var pausedState: SessionState {
        .paused(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            remaining: 13 * minute,
            focusedBefore: 12 * minute
        )
    }

    private var completeState: SessionState {
        .complete(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            completedAt: Clock.at(13, 55),
            focusedBefore: 7 * minute
        )
    }

    // MARK: - A second timer cannot be started

    func testStartIsRejectedWhileRunning() {
        let before = runningState
        XCTAssertEqual(SessionTransitions.start(before, duration: 45 * minute, now: now), before)
    }

    func testStartIsRejectedWhilePaused() {
        let before = pausedState
        XCTAssertEqual(SessionTransitions.start(before, duration: 45 * minute, now: now), before)
    }

    func testStartAnotherIsRejectedWhileRunning() {
        let before = runningState
        XCTAssertEqual(SessionTransitions.startAnother(before, duration: 45 * minute, now: now), before)
    }

    func testStartIsRejectedForANonPositiveDuration() {
        let before = SessionState.idle()
        XCTAssertEqual(SessionTransitions.start(before, duration: 0, now: now), before)
        XCTAssertEqual(SessionTransitions.start(before, duration: -60, now: now), before)
    }

    // MARK: - extend is legal only from complete

    func testExtendIsRejectedFromIdle() {
        let before = SessionState.idle()
        XCTAssertEqual(SessionTransitions.extend(before, now: now), before)
    }

    func testExtendIsRejectedWhileRunning() {
        let before = runningState
        XCTAssertEqual(SessionTransitions.extend(before, now: now), before)
    }

    func testExtendIsRejectedWhilePaused() {
        let before = pausedState
        XCTAssertEqual(SessionTransitions.extend(before, now: now), before)
    }

    func testExtendIsRejectedForANonPositiveStep() {
        let before = completeState
        XCTAssertEqual(SessionTransitions.extend(before, by: 0, now: now), before)
    }

    // MARK: - pause / resume

    func testPauseIsRejectedFromIdle() {
        let before = SessionState.idle()
        XCTAssertEqual(SessionTransitions.pause(before, now: now), before)
    }

    func testPauseIsRejectedWhileAlreadyPaused() {
        let before = pausedState
        XCTAssertEqual(SessionTransitions.pause(before, now: now), before)
    }

    func testPauseIsRejectedFromComplete() {
        let before = completeState
        XCTAssertEqual(SessionTransitions.pause(before, now: now), before)
    }

    func testResumeIsRejectedFromIdle() {
        let before = SessionState.idle()
        XCTAssertEqual(SessionTransitions.resume(before, now: now), before)
    }

    func testResumeIsRejectedWhileRunning() {
        let before = runningState
        XCTAssertEqual(SessionTransitions.resume(before, now: now), before)
    }

    func testResumeIsRejectedFromComplete() {
        let before = completeState
        XCTAssertEqual(SessionTransitions.resume(before, now: now), before)
    }

    // MARK: - reset and complete

    func testResetIsRejectedFromIdle() {
        let before = SessionState.idle(title: "Draft the memo")
        XCTAssertEqual(SessionTransitions.reset(before, now: now), before)
    }

    func testCompleteIsRejectedBeforeTheDeadline() {
        let before = runningState
        XCTAssertEqual(SessionTransitions.complete(before, now: Clock.at(14, 12, 59)), before)
    }

    func testCompleteIsRejectedFromEveryOtherStatus() {
        for before in [SessionState.idle(), pausedState, completeState] {
            XCTAssertEqual(SessionTransitions.complete(before, now: Clock.at(15, 0)), before)
        }
    }

    // MARK: - duration selection is legal only in idle

    func testSelectDurationIsRejectedWhileRunning() {
        let before = runningState
        XCTAssertEqual(SessionTransitions.selectDuration(before, duration: 45 * minute, now: now), before)
    }

    func testSelectDurationIsRejectedWhilePaused() {
        let before = pausedState
        XCTAssertEqual(
            SessionTransitions.selectDuration(before, duration: 45 * minute, now: now),
            before,
            "the plan must not change under a frozen remainder"
        )
    }

    func testSelectDurationIsRejectedFromComplete() {
        let before = completeState
        XCTAssertEqual(SessionTransitions.selectDuration(before, duration: 45 * minute, now: now), before)
    }

    func testSelectDurationIsRejectedForANonPositiveDuration() {
        let before = SessionState.idle()
        XCTAssertEqual(SessionTransitions.selectDuration(before, duration: 0, now: now), before)
    }
}
