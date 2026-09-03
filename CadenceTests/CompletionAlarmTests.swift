import XCTest
@testable import Cadence

/// D3's decisions, as pure functions of a record and a clock.
///
/// The framework half — `UNUserNotificationCenter`, authorization, the two separate
/// stores Stage 4 measured — is not testable here and is not what these cover. What is
/// covered is the thing that would silently break: *which* alarm each of two processes
/// decides to arm. The app and the widget extension run one code path over one record,
/// so if this function is right they cannot disagree about when a session ends, and if
/// it is wrong they cannot agree.
final class CompletionAlarmTests: XCTestCase {

    // MARK: - Arming

    /// The three edges D3 schedules on — `start`, `resume`, `extend` — all produce a
    /// running record with a live deadline, which is the state this arms from. Asserting
    /// against the transitions rather than against hand-built records is what makes the
    /// coverage a property of the state machine rather than of this test's imagination.
    func testTheThreeSchedulingEdgesArmTheirOwnDeadline() {
        let now = Clock.at(13, 48)

        let started = SessionTransitions.start(.idle(), duration: 25 * minute, now: now)
        XCTAssertEqual(
            CompletionAlarm.decision(for: started, now: now),
            .schedule(at: Clock.at(14, 13)),
            "start arms its own deadline"
        )

        let paused = SessionTransitions.pause(started, now: Clock.at(13, 58))
        let resumed = SessionTransitions.resume(paused, now: Clock.at(14, 3))
        XCTAssertEqual(
            CompletionAlarm.decision(for: resumed, now: Clock.at(14, 3)),
            .schedule(at: Clock.at(14, 18)),
            "resume arms the *new* deadline, not the one the pause froze"
        )

        let completed = SessionTransitions.reconciled(started, now: Clock.at(14, 13))
        let extended = SessionTransitions.extend(completed, now: Clock.at(14, 14))
        XCTAssertEqual(
            CompletionAlarm.decision(for: extended, now: Clock.at(14, 14)),
            .schedule(at: Clock.at(14, 19)),
            "extend arms five minutes from now, not from the deadline it passed"
        )
    }

    /// The two edges D3 cancels on, plus the two states that are not a running session.
    func testEveryStateThatIsNotARunningDeadlineCancels() {
        let now = Clock.at(13, 48)
        let started = SessionTransitions.start(.idle(), duration: 25 * minute, now: now)

        for (label, state) in [
            ("pause", SessionTransitions.pause(started, now: Clock.at(13, 58))),
            ("reset", SessionTransitions.reset(started, now: Clock.at(13, 58))),
            ("idle", SessionState.idle()),
            ("complete", SessionTransitions.reconciled(started, now: Clock.at(14, 13))),
        ] {
            XCTAssertEqual(
                CompletionAlarm.decision(for: state, now: Clock.at(13, 58)),
                .cancel,
                "\(label) holds no alarm"
            )
        }
    }

    /// The case that would trap rather than fail: a stored record still saying `running`
    /// with a deadline in the past, which is what the container holds whenever nothing
    /// was awake to bank the completion.
    ///
    /// It must cancel, not schedule. A `UNTimeIntervalNotificationTrigger` needs a
    /// positive interval, and an alarm for a deadline the user has already been shown
    /// as complete (D4) would announce a finish twice.
    func testARunningRecordWhoseDeadlineHasPassedCancels() {
        let elapsed = SessionState.running(
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            segmentStartedAt: Clock.at(13, 48)
        )

        XCTAssertEqual(
            CompletionAlarm.decision(for: elapsed, now: Clock.at(14, 20)),
            .cancel
        )
        // And the boundary: exactly at the deadline is already elapsed, because the
        // interval would be zero.
        XCTAssertEqual(
            CompletionAlarm.decision(for: elapsed, now: Clock.at(14, 13)),
            .cancel
        )
        XCTAssertEqual(
            CompletionAlarm.decision(for: elapsed, now: Clock.at(14, 12, 59)),
            .schedule(at: Clock.at(14, 13)),
            "one second short of the deadline is still an alarm to arm"
        )
    }

    // MARK: - Copy

    /// The banner names the session the way every other surface does (P5), and the
    /// fallback is computed rather than stored.
    func testTheBannerNamesTheSessionAsEverySurfaceDoes() {
        let plain = SessionState.running(
            plannedDuration: 25 * minute,
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            segmentStartedAt: Clock.at(13, 48)
        )
        XCTAssertEqual(CompletionAlarm.text(for: plain).title, "Session complete")
        XCTAssertEqual(CompletionAlarm.text(for: plain).body, plain.displayName)
        XCTAssertEqual(CompletionAlarm.text(for: plain).body, "25 minute session")

        var named = plain
        named.title = "Design review"
        XCTAssertEqual(CompletionAlarm.text(for: named).body, "Design review")
        XCTAssertNil(plain.title, "the fallback is never written back")
    }

    // MARK: - Delivery

    /// The duplicate case, at the only place it can be handled: a banner fires, and the
    /// process that is awake decides whether it still agrees with the container.
    func testABannerIsSuppressedWhenTheContainerDisagreesWithIt() {
        let now = Clock.at(14, 13)
        let started = SessionTransitions.start(.idle(), duration: 25 * minute, now: Clock.at(13, 48))

        // The ordinary case: nothing was awake, so the record still says `running` with
        // an elapsed deadline. That *is* a session that just finished.
        XCTAssertTrue(
            CompletionAlarm.agreesWithContainer(started, now: now),
            "an elapsed running record is a completion, not a disagreement"
        )

        // The banked case: some process got there first.
        XCTAssertTrue(
            CompletionAlarm.agreesWithContainer(
                SessionTransitions.reconciled(started, now: now),
                now: now
            )
        )

        // The duplicate: the widget armed an alarm, then the app paused the session.
        // The widget's request is unreachable and fires anyway; this is what stops it
        // being presented.
        XCTAssertFalse(
            CompletionAlarm.agreesWithContainer(
                SessionTransitions.pause(started, now: Clock.at(14, 0)),
                now: now
            ),
            "a paused session has not finished"
        )
        XCTAssertFalse(
            CompletionAlarm.agreesWithContainer(
                SessionTransitions.reset(started, now: Clock.at(14, 0)),
                now: now
            ),
            "a reset session has not finished"
        )
        // And a session the user restarted after the stale alarm was armed: the new
        // deadline has not arrived, so the old alarm must not announce it.
        let restarted = SessionTransitions.start(
            SessionTransitions.reconciled(started, now: now),
            duration: 45 * minute,
            now: now
        )
        XCTAssertFalse(CompletionAlarm.agreesWithContainer(restarted, now: now))
    }

    // MARK: - Identifiers

    /// One stable identifier per store is what makes arming idempotent: `add()` under an
    /// identifier already pending replaces the request rather than adding a second.
    func testTheIdentifierIsStable() {
        XCTAssertEqual(CompletionAlarm.identifier, "cadence.completion")
        XCTAssertEqual(CompletionAlarm.threadIdentifier, "cadence.session")
        XCTAssertNotEqual(
            CompletionAlarm.identifier,
            CompletionAlarm.threadIdentifier,
            "the request's identity and its Notification Center grouping are different things"
        )
    }

    // MARK: - Scheduler
    //
    // The scheduler's own behaviour is in `CompletionSchedulerTests`, against a recording
    // double. Two tests used to live here that looked like scheduler coverage and were
    // not: one drove `CompletionScheduler(center: { nil })` through both branches and
    // made no assertions at all, and one claimed to pin the `arming` asymmetry while
    // asserting only `CompletionAlarm.decision` — which is identical whatever `arming`
    // is. Both are replaced by tests that watch what reaches the centre.
}
