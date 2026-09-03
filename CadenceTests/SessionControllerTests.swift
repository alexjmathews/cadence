import XCTest
@testable import Cadence

/// The app-layer controller: the ticker's discipline (D1), the guards that decide
/// whether a preference moves, and the write-through contract with the container.
///
/// Against a scratch suite, so a test run cannot scribble on the session the
/// developer is actually using.
@MainActor
final class SessionControllerTests: XCTestCase {
    nonisolated private static let suiteName = "group.com.alexmathews.cadence.tests"

    /// A value wrapping the scratch suite; `UserDefaults(suiteName:)` hands back the
    /// same instance each time, so re-making it per access costs nothing and keeps
    /// the fixture free of mutable state to isolate.
    private var store: SharedStore {
        SharedStore(suiteName: Self.suiteName, reloadsWidgets: false)
    }

    nonisolated override func setUp() {
        super.setUp()
        Self.clearScratchSuite()
    }

    nonisolated override func tearDown() {
        Self.clearScratchSuite()
        super.tearDown()
    }

    nonisolated private static func clearScratchSuite() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let plist = URL.homeDirectory
            .appending(path: "Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    /// The ticker and `syncTicker` judge against the real clock, so fixture
    /// sessions are anchored to it rather than to `Clock`'s fixed afternoon.
    private func controller(
        seeding state: SessionState? = nil,
        preferences: Preferences? = nil
    ) -> SessionController {
        if let state { store.save(state) }
        if let preferences { store.save(preferences) }
        return SessionController(store: store, now: Date())
    }

    private var runningNow: SessionState {
        let now = Date()
        return .running(
            plannedDuration: 25 * minute,
            startedAt: now,
            endsAt: now.addingTimeInterval(25 * minute),
            segmentStartedAt: now
        )
    }

    // MARK: - Ticker discipline (D1)

    func testTheTickerRunsOnlyWhileRunning() {
        XCTAssertTrue(controller(seeding: runningNow).isTicking, "running redraws")

        XCTAssertFalse(controller(seeding: .idle()).isTicking, "idle has nothing to redraw")
        XCTAssertFalse(
            controller(
                seeding: .paused(startedAt: Date(), remaining: 10 * minute, focusedBefore: 0)
            ).isTicking,
            "paused is frozen"
        )
        XCTAssertFalse(
            controller(
                seeding: .complete(
                    startedAt: Date().addingTimeInterval(-25 * minute),
                    completedAt: Date(),
                    focusedBefore: 25 * minute
                )
            ).isTicking,
            "complete is terminal"
        )
    }

    /// A deadline that elapsed while the app was quit reads as complete on load
    /// (D4), so the ticker must never start for it.
    func testAnElapsedSessionLoadsWithoutStartingTheTicker() {
        let started = Date().addingTimeInterval(-30 * minute)
        let controller = controller(
            seeding: .running(
                startedAt: started,
                endsAt: Date().addingTimeInterval(-5 * minute),
                segmentStartedAt: started
            )
        )

        XCTAssertEqual(controller.status, .complete)
        XCTAssertFalse(controller.isTicking)
    }

    func testPausingStopsTheTickerAndResumingRestartsIt() {
        let controller = controller(seeding: runningNow)
        XCTAssertTrue(controller.isTicking)

        controller.pause()
        XCTAssertEqual(controller.status, .paused)
        XCTAssertFalse(controller.isTicking)

        controller.resume()
        XCTAssertEqual(controller.status, .running)
        XCTAssertTrue(controller.isTicking)

        controller.reset()
        XCTAssertFalse(controller.isTicking)
    }

    // MARK: - Preset selection

    func testSelectingAPresetWhileIdleRescopesThePlanAndRemembersIt() {
        let controller = controller(seeding: .idle(plannedDuration: 25 * minute))

        controller.select(DurationPreset.fixed)

        XCTAssertEqual(controller.state.plannedDuration, 45 * minute)
        XCTAssertEqual(controller.preferences.lastUsedDuration, 45 * minute)
        XCTAssertEqual(store.loadPreferences().lastUsedDuration, 45 * minute)
    }

    /// Duration selection is legal only in `idle` (§5). The guard has to be the
    /// precondition and not the resulting plan: `selectDuration` rejects by
    /// returning its input, which is indistinguishable from a duration that was
    /// already selected, so inferring legality from the result let a running
    /// session rewrite the preference.
    func testSelectingAPresetWhileRunningLeavesBothThePlanAndThePreferenceAlone() {
        let controller = controller(
            seeding: runningNow,
            preferences: Preferences(lastUsedDuration: 25 * minute)
        )

        controller.select(DurationPreset.fixed)

        XCTAssertEqual(controller.state.plannedDuration, 25 * minute)
        XCTAssertEqual(controller.preferences.lastUsedDuration, 25 * minute)
        XCTAssertEqual(store.loadPreferences().lastUsedDuration, 25 * minute)
    }

    /// The nastier variant: `+5 min` grows the plan, so a clock-target row can come
    /// to match `plannedDuration` exactly while a session runs.
    func testAPresetMatchingAnExtendedPlanStillDoesNotMoveThePreference() {
        let started = Date().addingTimeInterval(-25 * minute)
        let controller = controller(
            seeding: .complete(
                startedAt: started,
                completedAt: Date().addingTimeInterval(-1),
                focusedBefore: 25 * minute
            ),
            preferences: Preferences(lastUsedDuration: 25 * minute)
        )

        controller.extend()
        XCTAssertEqual(controller.state.plannedDuration, 30 * minute)

        controller.select(DurationPreset(id: "30m", title: "30 minutes", duration: 30 * minute))

        XCTAssertEqual(controller.preferences.lastUsedDuration, 25 * minute)
    }

    // MARK: - Typed duration

    /// The window's editable numerals commit through the same door as a preset
    /// row, so they carry the same guard and the same preference write.
    func testATypedDurationWhileIdleRescopesThePlanAndRemembersIt() {
        let controller = controller(seeding: .idle(plannedDuration: 25 * minute))

        controller.selectDuration(50 * minute)

        XCTAssertEqual(controller.state.plannedDuration, 50 * minute)
        XCTAssertEqual(store.loadPreferences().lastUsedDuration, 50 * minute)
    }

    func testATypedDurationWhilePausedIsRefused() {
        let started = Date().addingTimeInterval(-10 * minute)
        let controller = controller(
            seeding: .paused(startedAt: started, remaining: 15 * minute, focusedBefore: 10 * minute),
            preferences: Preferences(lastUsedDuration: 25 * minute)
        )

        controller.selectDuration(50 * minute)

        XCTAssertEqual(controller.state.plannedDuration, 25 * minute)
        XCTAssertEqual(store.loadPreferences().lastUsedDuration, 25 * minute)
    }

    /// `SessionTransitions.selectDuration` guards `duration > 0` as well as the
    /// status, and rejects by returning its input — so the preference has to follow
    /// the plan rather than the press. §2.2 says `lastUsedDuration` exists so idle
    /// shows something sensible, and `lastUsedDuration: 0` beside `plannedDuration: 9`
    /// is neither sensible nor true.
    func testADurationOfZeroMovesNeitherThePlanNorThePreference() {
        let controller = controller(
            seeding: .idle(plannedDuration: 25 * minute),
            preferences: Preferences(lastUsedDuration: 25 * minute)
        )

        controller.selectDuration(0)

        XCTAssertEqual(controller.state.plannedDuration, 25 * minute)
        XCTAssertEqual(controller.preferences.lastUsedDuration, 25 * minute)
        XCTAssertEqual(store.loadPreferences().lastUsedDuration, 25 * minute)
    }

    func testANegativeDurationIsRefusedTheSameWay() {
        let controller = controller(
            seeding: .idle(plannedDuration: 25 * minute),
            preferences: Preferences(lastUsedDuration: 25 * minute)
        )

        controller.selectDuration(-60)

        XCTAssertEqual(controller.state.plannedDuration, 25 * minute)
        XCTAssertEqual(store.loadPreferences().lastUsedDuration, 25 * minute)
    }

    // MARK: - Banking a completion the ticker noticed (D4)

    /// The ticker refreshing `now` is enough for every surface to *read* complete
    /// (D4), but the stored record still said `running` with an elapsed `endsAt`, so
    /// `completedAt` was nil and the window's summary line had nothing to print until
    /// the app was deactivated and reactivated.
    ///
    /// Persisting the derived result is reconciliation, not the ticker deciding
    /// completion: the deadline decided, and `reconciled` is the same function every
    /// other entry point runs.
    func testTheTickerBanksACompletionSoTheSummaryLineExists() {
        let started = Date().addingTimeInterval(-2 * minute)
        let controller = controller(
            seeding: .running(
                plannedDuration: 2 * minute,
                startedAt: started,
                endsAt: Date().addingTimeInterval(0.4),
                segmentStartedAt: started
            )
        )
        XCTAssertTrue(controller.isTicking)
        XCTAssertNil(controller.state.completedAt)

        wait(seconds: 2.5)

        XCTAssertEqual(controller.status, .complete)
        XCTAssertFalse(controller.isTicking, "a banked completion stops the redraw")
        XCTAssertEqual(controller.state.status, .complete, "the record, not just the derivation")
        XCTAssertNotNil(controller.state.completedAt)
        XCTAssertNotNil(controller.state.span, "which is what the summary line is built from")
        XCTAssertNotNil(controller.state.summaryLine(Date()))

        // **`loadSessionState` is not the check, and this is the whole of the defect it
        // used to hide.** It reconciles on read (D4), so it answers `.complete` for a
        // record that still says `running` with an elapsed `endsAt` — which is precisely
        // what the container held while this test passed and the completion was never
        // banked. The stored bytes are what has to be asserted.
        let stored = store.loadStoredSessionState()
        XCTAssertEqual(stored.status, .complete, "the bytes in the container, not their reconciliation")
        XCTAssertNotNil(stored.completedAt, "and `completedAt` is what the summary line needs")
        XCTAssertNil(stored.endsAt, "a banked completion carries no deadline (§2.1)")
        XCTAssertNil(stored.segmentStartedAt)
    }

    /// **The wake path, which the ticker cannot cover.**
    ///
    /// `refresh()` is what `NSWorkspace.didWakeNotification` calls. A machine that slept
    /// across a deadline wakes with a container that still says `running` with an elapsed
    /// `endsAt` — and the ticker is no help, because `syncTicker` invalidates it for a
    /// session that is no longer running, so the tick that would have banked the
    /// completion never arrives. Banking inside `refresh` is the only thing that makes
    /// "the deadline elapsed while asleep" *persist* rather than merely render.
    ///
    /// This is unfenced without this test: deleting `bankCompletion` from `refresh` left
    /// the whole suite green, because `testTheTickerBanksACompletionSoTheSummaryLineExists`
    /// reaches the same lines by the tick path.
    ///
    /// The record is written **directly to the store** after the controller exists, so
    /// neither the initialiser's own bank nor the ticker can be what banks it: at the
    /// moment `refresh()` is called the controller is idle and holds no timer, exactly as
    /// it would be after a sleep long enough to have stopped one. And the assertion is
    /// `loadStoredSessionState` — the unreconciled bytes — because `loadSessionState`
    /// reconciles on read and would answer `.complete` for the very record whose failure
    /// to be banked is the defect.
    func testWakingAfterTheDeadlineElapsedBanksTheCompletion() {
        let controller = controller(seeding: .idle())
        XCTAssertFalse(controller.isTicking)

        // What the container holds when nothing was awake to notice the deadline.
        let started = Date().addingTimeInterval(-30 * minute)
        store.save(.running(
            plannedDuration: 25 * minute,
            startedAt: started,
            endsAt: started.addingTimeInterval(25 * minute),
            segmentStartedAt: started
        ))
        XCTAssertEqual(
            store.loadStoredSessionState().status, .running,
            "the fixture is the unbanked record, or this test proves nothing"
        )

        controller.refresh()

        let stored = store.loadStoredSessionState()
        XCTAssertEqual(
            stored.status, .complete,
            "waking across a deadline has to bank it, not merely render it"
        )
        XCTAssertNotNil(
            stored.completedAt,
            "without this the window's summary line has nothing to print"
        )
        XCTAssertNil(stored.endsAt, "a banked completion carries no deadline (§2.1)")
        XCTAssertNil(stored.segmentStartedAt)

        // And the live view agrees with the bytes, so the surfaces draw the record that
        // was written rather than a reconciliation of one that was not.
        XCTAssertEqual(controller.state.status, .complete)
        XCTAssertNotNil(controller.state.summaryLine(Date()))
        XCTAssertFalse(controller.isTicking)
    }

    /// Idempotent: `reconciled` returns an already-banked completion unchanged, so a
    /// second pass neither rewrites the record nor moves `completedAt`.
    func testBankingACompletionTwiceChangesNothing() {
        let started = Date().addingTimeInterval(-2 * minute)
        let controller = controller(
            seeding: .running(
                plannedDuration: 2 * minute,
                startedAt: started,
                endsAt: Date().addingTimeInterval(0.4),
                segmentStartedAt: started
            )
        )

        wait(seconds: 2.5)
        let banked = controller.state
        let bankedBytes = store.loadStoredSessionState()

        controller.refresh()

        XCTAssertEqual(controller.state, banked)
        XCTAssertEqual(store.loadSessionState(now: Date()), banked)
        // Idempotence measured where it matters: the *stored* record did not move, so
        // the second pass wrote nothing and reloaded no timelines.
        XCTAssertEqual(store.loadStoredSessionState(), bankedBytes)
        XCTAssertEqual(bankedBytes.status, .complete)
    }

    // MARK: - The alarm the controller owns (D3)

    /// **The observation path cancels but never arms, and the flag is the only thing that
    /// says so.** `refresh()` runs on wake, on activation and on a KVO notification — all
    /// three are the app reading a record *another* process wrote, and the process that
    /// wrote it already armed its own alarm. A second one in this store is D3's avoidable
    /// duplicate: one session announcing itself twice for no reason but an activation.
    ///
    /// Flipping `reconcileAlarm(arming: false)` to `true` was measured leaving the whole
    /// suite green, because nothing observed what reached a notification centre.
    func testRefreshCancelsAStaleAlarmWithoutArmingASecondOne() {
        let centre = RecordingCentre()
        let scheduler = CompletionScheduler(center: { centre })

        // Constructed over an idle record, so the initialiser's own arm — which *is* a
        // first schedule, this process's store being empty — is not what is measured.
        let controller = SessionController(store: store, scheduler: scheduler, now: Date())
        XCTAssertEqual(centre.added, [], "an idle relaunch has no alarm to arm")

        // Another process starts a session and arms it in *its* store.
        let now = Date()
        store.save(.running(
            plannedDuration: 25 * minute,
            startedAt: now,
            endsAt: now.addingTimeInterval(25 * minute),
            segmentStartedAt: now
        ))

        controller.refresh()

        XCTAssertEqual(controller.status, .running, "the record was adopted")
        XCTAssertEqual(
            centre.added, [],
            "an observation must not arm a second alarm for a session whose writer armed one"
        )

        // The other half: the same call over a record that has stopped is the cancel only
        // this side can reach, since a widget `pause` cannot touch the app's store.
        store.save(.paused(startedAt: now, remaining: 10 * minute, focusedBefore: 0))
        controller.refresh()

        assertCancelled(centre)
        XCTAssertEqual(centre.added, [], "and still arms nothing")
    }

    /// A transition the *app* performs is a write, so it owns the alarm — the other side
    /// of the asymmetry above, asserted through the controller rather than the scheduler
    /// so that `apply`'s call is fenced too.
    func testAPressInTheAppArmsAndCancelsItsOwnAlarm() throws {
        let centre = RecordingCentre()
        let scheduler = CompletionScheduler(center: { centre })
        let controller = SessionController(
            store: store,
            scheduler: scheduler,
            now: Date()
        )

        controller.selectDuration(30 * minute)
        controller.start()
        XCTAssertEqual(centre.added.count, 1, "a start in the app arms in the app's store")
        XCTAssertEqual(
            try XCTUnwrap(centre.added.first?.interval), 30 * minute, accuracy: 1
        )

        controller.pause()
        assertCancelled(centre)
    }

    /// Cancelling is idempotent by construction — removing nothing is free — and the
    /// container observation means one write can reach `refresh` more than once, so the
    /// assertion is *that* the alarm was cancelled and never *how many times*.
    private func assertCancelled(
        _ centre: RecordingCentre,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(centre.removedPending.isEmpty, "the alarm was never cancelled", file: file, line: line)
        XCTAssertEqual(
            Set(centre.removedPending.flatMap { $0 }), [CompletionAlarm.identifier],
            "the scheduler removed something other than its own request",
            file: file, line: line
        )
    }

    private func wait(seconds: TimeInterval) {
        let elapsed = expectation(description: "the ticker has had a chance to fire")
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in elapsed.fulfill() }
        wait(for: [elapsed], timeout: seconds + 5)
    }

    // MARK: - End-early buffer

    /// The buffer is a preference in the App Group, so it survives the process it
    /// was set in (§2.2) — this is the relaunch round-trip in miniature.
    func testTheBufferIsWrittenToTheContainerAndReadBackByAFreshController() {
        let controller = controller()

        controller.setBuffer(180)

        XCTAssertEqual(controller.preferences.endEarlyBuffer, 180)
        XCTAssertEqual(
            SessionController(store: store, now: Date()).preferences.endEarlyBuffer,
            180
        )
    }

    /// Changing it mid-session retimes nothing: the buffer is materialised into a
    /// deadline at start time (P4), never applied to one already running.
    func testChangingTheBufferDoesNotRetimeARunningSession() {
        let running = runningNow
        let controller = controller(seeding: running)

        controller.setBuffer(0)

        XCTAssertEqual(controller.state.endsAt, running.endsAt)
        XCTAssertEqual(controller.state.plannedDuration, running.plannedDuration)
    }

    // MARK: - Write-through

    func testATransitionTheContainerRefusesLeavesTheStateAlone() throws {
        // `UserDefaults(suiteName:)` refuses the main bundle's own identifier, so
        // this store has no container to write to.
        let bundleID = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let unusable = SharedStore(suiteName: bundleID, reloadsWidgets: false)
        XCTAssertFalse(unusable.save(SessionState()), "the suite must be unresolvable")

        let controller = SessionController(store: unusable, now: Date())
        let before = controller.state

        controller.start()

        XCTAssertEqual(controller.state, before, "an unwritten transition did not happen")
        XCTAssertFalse(controller.isTicking)
    }

    /// P2: the container is canonical and the in-memory copy is a cache that
    /// re-reads. This is the path activation, wake and KVO all land on.
    func testRefreshAdoptsAWriteMadeBehindTheControllersBack() {
        let controller = controller(seeding: .idle(plannedDuration: 25 * minute))
        XCTAssertFalse(controller.isTicking)

        store.save(runningNow)
        controller.refresh()

        XCTAssertEqual(controller.status, .running)
        XCTAssertTrue(controller.isTicking, "adopting a running session starts the redraw")
    }

    /// A press arriving inside KVO's latency window must not be computed against
    /// the stale cache, or it writes a state one revision old back over the newer
    /// record (D2).
    func testATransitionAppliesToTheStoredStateRatherThanTheStaleCache() {
        let controller = controller(seeding: .idle(plannedDuration: 25 * minute))

        // Another writer starts a titled session; the controller has not heard yet.
        store.save(
            .running(
                title: "Design review",
                startedAt: Date(),
                endsAt: Date().addingTimeInterval(10 * minute),
                segmentStartedAt: Date()
            )
        )

        controller.pause()

        XCTAssertEqual(controller.status, .paused, "pause applied to the newer record")
        XCTAssertEqual(controller.state.title, "Design review")
        XCTAssertEqual(store.loadSessionState(now: Date()).status, .paused)
    }

    /// `start` is illegal from `running` (§5), and a rejected transition still
    /// hands back the reconciled base — so the cache ends up agreeing with disk
    /// either way.
    func testARejectedTransitionStillLeavesTheCacheAgreeingWithDisk() {
        let controller = controller(seeding: runningNow)
        let stored = runningNow
        store.save(stored)

        controller.start()

        XCTAssertEqual(controller.state, store.loadSessionState(now: Date()))
    }
}
