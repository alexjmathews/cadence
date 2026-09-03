import XCTest
@testable import Cadence

/// The widget's write side (D2): guards, reconciliation, and the container re-read.
///
/// The interesting cases are all the ones where the widget is *wrong* — a timeline
/// generated before the app changed the session, a `Pause` on a card that has since
/// completed, a meeting row whose event has gone. None of them may crash and none may
/// clobber a newer record.
final class WidgetActionsTests: XCTestCase {
    private let suiteName = "group.com.alexmathews.cadence.tests"
    private var store: SharedStore!

    override func setUp() {
        super.setUp()
        clearScratchSuite()
        store = SharedStore(suiteName: suiteName, reloadsWidgets: false)
    }

    override func tearDown() {
        clearScratchSuite()
        store = nil
        super.tearDown()
    }

    private func clearScratchSuite() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let plist = URL.homeDirectory
            .appending(path: "Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    private func next(
        _ action: WidgetAction,
        _ state: SessionState,
        snapshot: CalendarSnapshot? = nil,
        buffer: TimeInterval = 120,
        at now: Date
    ) -> SessionState {
        var preferences = Preferences()
        preferences.endEarlyBuffer = buffer
        return WidgetActions.next(
            action,
            state: state,
            snapshot: snapshot,
            preferences: preferences,
            now: now,
            calendar: Clock.calendar
        )
    }

    private func event(
        id: String = "event|1",
        title: String = "Design review",
        at startsAt: Date
    ) -> EventOccurrence {
        EventOccurrence(
            id: id,
            title: title,
            startsAt: startsAt,
            endsAt: startsAt.addingTimeInterval(30 * minute)
        )
    }

    private func snapshot(
        _ events: [EventOccurrence],
        at now: Date,
        access: CalendarAccess = .authorized
    ) -> CalendarSnapshot {
        CalendarSnapshot(
            day: Clock.startOfDay(now),
            events: events,
            lastSyncedAt: now,
            access: access
        )
    }

    // MARK: - Transitions

    func testStartUsesTheStoredPlanRatherThanAnythingTheWidgetRemembered() {
        let now = Clock.at(14, 0)
        let result = next(.start, .idle(plannedDuration: 45 * minute), at: now)

        XCTAssertEqual(result.status, .running)
        XCTAssertEqual(result.plannedDuration, 45 * minute)
        XCTAssertEqual(result.endsAt, Clock.at(14, 45))
        XCTAssertNil(result.title, "a plain duration session stores no name")
        assertInvariants(result)
    }

    /// The same action is the `Start another` edge, which is what makes the complete
    /// card's primary one intent rather than two.
    func testStartIsAlsoTheStartAnotherEdge() {
        let now = Clock.at(14, 20)
        let result = next(
            .start,
            .complete(
                title: "Design review",
                startedAt: Clock.at(13, 48),
                completedAt: Clock.at(14, 13),
                focusedBefore: 25 * minute
            ),
            at: now
        )

        XCTAssertEqual(result.status, .running)
        XCTAssertEqual(result.startedAt, now)
        XCTAssertEqual(result.focusedBefore, 0, "a new run banks no old focus")
        XCTAssertNil(result.title, "a full plan replacement drops the old name")
        assertInvariants(result)
    }

    func testASuggestionRowStartsTheLengthItsLabelPromised() {
        let now = Clock.at(14, 0)
        let result = next(.startDuration(45 * minute), .idle(), at: now)

        XCTAssertEqual(result.plannedDuration, 45 * minute)
        XCTAssertEqual(result.endsAt, Clock.at(14, 45))
    }

    func testPauseResumeResetAndExtendMatchTheSharedTransitions() {
        let running = SessionState.running(
            startedAt: Clock.at(14, 0),
            endsAt: Clock.at(14, 25),
            segmentStartedAt: Clock.at(14, 0)
        )
        let paused = next(.pause, running, at: Clock.at(14, 10))
        XCTAssertEqual(paused, SessionTransitions.pause(running, now: Clock.at(14, 10)))

        let resumed = next(.resume, paused, at: Clock.at(14, 20))
        XCTAssertEqual(resumed, SessionTransitions.resume(paused, now: Clock.at(14, 20)))

        let reset = next(.reset, resumed, at: Clock.at(14, 21))
        XCTAssertEqual(reset, SessionTransitions.reset(resumed, now: Clock.at(14, 21)))

        let complete = SessionState.complete(
            startedAt: Clock.at(13, 48),
            completedAt: Clock.at(14, 13),
            focusedBefore: 25 * minute
        )
        let extended = next(.extend, complete, at: Clock.at(14, 20))
        XCTAssertEqual(extended, SessionTransitions.extend(complete, now: Clock.at(14, 20)))
        XCTAssertEqual(extended.endsAt, Clock.at(14, 25))
    }

    // MARK: - Guards

    /// A widget's timeline is a snapshot, so it can legitimately offer a control the
    /// state machine forbids. Every one of these must cost nothing.
    func testIllegalRequestsAreNoOps() {
        let now = Clock.at(14, 10)
        let idle = SessionState.idle(title: "Design review")
        let running = SessionState.running(
            startedAt: Clock.at(14, 0),
            endsAt: Clock.at(14, 25),
            segmentStartedAt: Clock.at(14, 0)
        )
        let paused = SessionState.paused(
            startedAt: Clock.at(14, 0),
            remaining: 15 * minute,
            focusedBefore: 10 * minute
        )

        XCTAssertEqual(next(.pause, idle, at: now), idle, "nothing to pause")
        XCTAssertEqual(next(.resume, idle, at: now), idle, "nothing to resume")
        XCTAssertEqual(next(.resume, running, at: now), running, "already running")
        XCTAssertEqual(next(.pause, paused, at: now), paused, "already paused")
        XCTAssertEqual(next(.reset, idle, at: now), idle, "already reset")
        XCTAssertEqual(next(.extend, running, at: now), running, "extend is complete-only")
        XCTAssertEqual(next(.extend, paused, at: now), paused, "extend is complete-only")
        XCTAssertEqual(next(.start, running, at: now), running, "no second timer")
        XCTAssertEqual(next(.start, paused, at: now), paused, "no second timer")
        XCTAssertEqual(
            next(.startDuration(45 * minute), running, at: now),
            running,
            "a stale suggestion row cannot retime a running session"
        )
    }

    /// Stage 0's deliberate consequence: a rejected transition returns the
    /// *reconciled* state, so a stale `Pause` on an elapsed session persists the
    /// completion rather than handing back a `running` no surface agrees with.
    func testAStalePauseOnAnElapsedSessionReturnsTheCompletion() {
        let running = SessionState.running(
            title: "Design review",
            startedAt: Clock.at(14, 0),
            endsAt: Clock.at(14, 25),
            segmentStartedAt: Clock.at(14, 0)
        )
        let result = next(.pause, running, at: Clock.at(14, 40))

        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(result.completedAt, Clock.at(14, 25))
        XCTAssertEqual(result.focusedBefore, 25 * minute)
        assertInvariants(result)
    }

    // MARK: - Meeting start

    func testAMeetingRowMaterialisesTheBufferedDeadlineAtPressTime() {
        let now = Clock.at(14, 0)
        let meeting = event(at: Clock.at(15, 0))
        let result = next(
            .startMeeting(eventKey: meeting.id),
            .idle(),
            snapshot: snapshot([meeting], at: now),
            buffer: 120,
            at: now
        )

        XCTAssertEqual(result.status, .running)
        XCTAssertEqual(result.title, "Design review")
        XCTAssertEqual(result.linkedEventKey, meeting.id)
        // 3:00 less the 2 minute buffer, materialised from `now` (P4).
        XCTAssertEqual(result.endsAt, Clock.at(14, 58))
        XCTAssertEqual(result.plannedDuration, 58 * minute)
        assertInvariants(result)
    }

    func testTheSavedBufferIsReadAtPressTimeNotBakedIntoTheRow() {
        let now = Clock.at(14, 0)
        let meeting = event(at: Clock.at(15, 0))
        let day = snapshot([meeting], at: now)

        XCTAssertEqual(
            next(.startMeeting(eventKey: meeting.id), .idle(), snapshot: day, buffer: 0, at: now).endsAt,
            Clock.at(15, 0)
        )
        XCTAssertEqual(
            next(.startMeeting(eventKey: meeting.id), .idle(), snapshot: day, buffer: 180, at: now).endsAt,
            Clock.at(14, 57)
        )
    }

    /// The widget cannot re-resolve the key against EventKit, so the snapshot is all
    /// it has — and a key the snapshot no longer carries starts nothing. It must not
    /// silently fall back to the stored plan: the row promised a meeting.
    func testAMeetingRowWhoseEventHasGoneStartsNothing() {
        let now = Clock.at(14, 0)
        let idle = SessionState.idle()

        XCTAssertEqual(
            next(
                .startMeeting(eventKey: "vanished|1"),
                idle,
                snapshot: snapshot([event(at: Clock.at(15, 0))], at: now),
                at: now
            ),
            idle
        )
        XCTAssertEqual(
            next(.startMeeting(eventKey: "event|1"), idle, snapshot: nil, at: now),
            idle,
            "no snapshot, no meeting"
        )
    }

    func testAMeetingRowIsRefusedWhenTheSnapshotIsStaleOrAccessIsOff() {
        let now = Clock.at(14, 0)
        let meeting = event(at: Clock.at(15, 0))
        let idle = SessionState.idle()

        var yesterday = snapshot([meeting], at: now)
        yesterday.day = Clock.startOfDay(Clock.on(day: 3, 14, 0))
        XCTAssertEqual(
            next(.startMeeting(eventKey: meeting.id), idle, snapshot: yesterday, at: now),
            idle,
            "never yesterday's meetings"
        )

        XCTAssertEqual(
            next(
                .startMeeting(eventKey: meeting.id),
                idle,
                snapshot: snapshot([meeting], at: now, access: .denied),
                at: now
            ),
            idle,
            "revoked access clears the widget's offer too"
        )
    }

    /// A press that arrived after the event stopped being worth timing starts nothing
    /// rather than a twenty-second session.
    func testAMeetingRowRefusesOnceTheBufferHasEatenTheLead() {
        let now = Clock.at(14, 0)
        let meeting = event(at: Clock.at(14, 2, 30))
        let idle = SessionState.idle()

        XCTAssertEqual(
            next(.startMeeting(eventKey: meeting.id), idle, snapshot: snapshot([meeting], at: now), buffer: 120, at: now),
            idle
        )
    }

    func testAMeetingRowCannotStartOverARunningSession() {
        let now = Clock.at(14, 0)
        let meeting = event(at: Clock.at(15, 0))
        let running = SessionState.running(
            startedAt: Clock.at(13, 50),
            endsAt: Clock.at(14, 15),
            segmentStartedAt: Clock.at(13, 50)
        )

        XCTAssertEqual(
            next(.startMeeting(eventKey: meeting.id), running, snapshot: snapshot([meeting], at: now), at: now),
            running
        )
    }

    // MARK: - The container re-read

    /// D2's hazard, reproduced: the widget's timeline says `idle`, but the app has
    /// since started a session. The press must be judged against the container.
    func testPerformTransitionsFromTheContainerNotFromTheCaller() {
        let now = Clock.at(14, 10)
        let running = SessionState.running(
            title: "Design review",
            startedAt: Clock.at(14, 0),
            endsAt: Clock.at(14, 25),
            segmentStartedAt: Clock.at(14, 0)
        )
        store.save(running)

        // The card was drawn from an `idle` timeline, so it offered `Start`.
        let result = WidgetActions.perform(.start, store: store, now: now, calendar: Clock.calendar)

        XCTAssertEqual(result.state, running, "the guard saw the container's running session")
        XCTAssertFalse(result.changed, "and reported that nothing was written")
        XCTAssertEqual(
            store.loadSessionState(now: now),
            running,
            "and the newer record was not clobbered"
        )
    }

    func testPerformWritesThroughAndReturnsWhatTheContainerNowHolds() {
        let now = Clock.at(14, 0)
        store.save(.idle(plannedDuration: 30 * minute))

        let result = WidgetActions.perform(.start, store: store, now: now, calendar: Clock.calendar)

        XCTAssertEqual(result.state.status, .running)
        XCTAssertEqual(result.state.endsAt, Clock.at(14, 30))
        XCTAssertTrue(result.changed, "an accepted press reports the write it made")
        XCTAssertEqual(store.loadSessionState(now: now), result.state)
    }

    func testPerformReadsTheBufferAndTheSnapshotFromTheContainer() {
        let now = Clock.at(14, 0)
        let meeting = event(at: Clock.at(15, 0))
        store.save(SessionState.idle())
        store.save(snapshot([meeting], at: now))
        var preferences = Preferences()
        preferences.endEarlyBuffer = 180
        store.save(preferences)

        let result = WidgetActions.perform(
            .startMeeting(eventKey: meeting.id),
            store: store,
            now: now,
            calendar: Clock.calendar
        )

        XCTAssertEqual(result.state.title, "Design review")
        XCTAssertEqual(result.state.endsAt, Clock.at(14, 57), "the saved buffer, not a default")
    }

    /// A refused press leaves the record byte-identical, so a widget reload cannot
    /// show a state the container never held.
    func testARefusedPressWritesNothing() {
        let now = Clock.at(14, 0)
        let idle = SessionState.idle(title: "Design review")
        store.save(idle)

        // `changed` is what the intent reloads its timelines on: a refused press is
        // the one press `SharedStore` did *not* reload for, and the one whose stale
        // card most needs redrawing.
        XCTAssertEqual(
            WidgetActions.perform(.extend, store: store, now: now, calendar: Clock.calendar),
            WidgetActions.Outcome(state: idle, changed: false)
        )
        XCTAssertEqual(store.loadSessionState(now: now), idle)
    }

    // MARK: - The alarm the press owns (D3)

    /// **A widget press owns the alarm it implies, and this is the case D3 was amended
    /// for.** With the app quit for the whole session — which D2 makes the ordinary widget
    /// case — there is nobody else to arm the completion alarm and nobody else to notice
    /// it was never armed. Deleting the one `scheduler?.reconcile` line in `perform` was
    /// measured leaving the entire suite green while removing the alarm from every widget
    /// press, every `cadence://` command and every Shortcuts invocation.
    ///
    /// The scheduler is the shared one from `Shared/`, over a recording centre — so this
    /// asserts the widget's store gets the same request the app's would, which is the
    /// whole reason the scheduler lives in `Shared/` and takes its centre as an argument.
    func testAnAcceptedPressArmsTheAlarmInThisProcessesOwnStore() throws {
        let now = Clock.at(14, 0)
        store.save(.idle(plannedDuration: 30 * minute))

        let centre = RecordingCentre()
        let result = WidgetActions.perform(
            .start,
            store: store,
            scheduler: CompletionScheduler(center: { centre }),
            now: now,
            calendar: Clock.calendar
        )

        XCTAssertTrue(result.changed)
        XCTAssertEqual(centre.added.count, 1, "the press that wrote the record armed its alarm")
        XCTAssertEqual(centre.added.first?.identifier, CompletionAlarm.identifier)
        XCTAssertEqual(
            try XCTUnwrap(centre.added.first?.interval), 30 * minute, accuracy: 0.001,
            "at the deadline the record it just wrote implies"
        )
    }

    /// `pause` and `reset` are the other half: this process performed the transition, so
    /// this process cancels in its own store.
    func testAPressThatStopsTheSessionCancelsTheAlarm() {
        let now = Clock.at(14, 0)
        store.save(.running(
            plannedDuration: 25 * minute,
            startedAt: Clock.at(13, 50),
            endsAt: Clock.at(14, 15),
            segmentStartedAt: Clock.at(13, 50)
        ))

        let centre = RecordingCentre()
        WidgetActions.perform(
            .pause,
            store: store,
            scheduler: CompletionScheduler(center: { centre }),
            now: now,
            calendar: Clock.calendar
        )

        XCTAssertEqual(centre.removedPending, [[CompletionAlarm.identifier]])
        XCTAssertEqual(centre.added, [])
    }

    /// A press a guard refused wrote nothing, so nothing about the alarm changed either —
    /// `perform` returns before it reaches the scheduler. A `Pause` on a stale card must
    /// not cancel the alarm of a session that is still running.
    func testARefusedPressLeavesTheAlarmAlone() {
        let now = Clock.at(14, 0)
        store.save(SessionState.idle())

        let centre = RecordingCentre()
        let result = WidgetActions.perform(
            .extend,
            store: store,
            scheduler: CompletionScheduler(center: { centre }),
            now: now,
            calendar: Clock.calendar
        )

        XCTAssertFalse(result.changed)
        XCTAssertEqual(centre.added, [])
        XCTAssertEqual(centre.removedPending, [], "a refused press is not a cancel")
    }

    // MARK: - Intent wire form

    /// The intent carries the action across a process boundary as three parameters.
    /// Every case has to survive the trip, and a malformed one has to fail as
    /// "nothing happened".
    func testEveryActionRoundTripsThroughItsIntentParameters() {
        let actions: [WidgetAction] = [
            .start,
            .startDuration(45 * minute),
            .startMeeting(eventKey: "event|1"),
            .pause,
            .resume,
            .reset,
            .extend,
        ]

        for action in actions {
            var duration: Double = 0
            var eventKey = ""
            if case .startDuration(let seconds) = action { duration = seconds }
            if case .startMeeting(let key) = action { eventKey = key }

            XCTAssertEqual(
                WidgetAction(kind: action.kind.rawValue, duration: duration, eventKey: eventKey),
                action
            )
        }
    }

    func testAMalformedIntentDecodesToNothing() {
        XCTAssertNil(WidgetAction(kind: "teleport", duration: 0, eventKey: ""))
        XCTAssertNil(
            WidgetAction(kind: "startDuration", duration: 0, eventKey: ""),
            "a zero-length session is not a session"
        )
        XCTAssertNil(
            WidgetAction(kind: "startMeeting", duration: 0, eventKey: ""),
            "a meeting with no key is not a meeting"
        )
    }
}
