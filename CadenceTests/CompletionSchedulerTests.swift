import UserNotifications
import XCTest
@testable import Cadence

/// D3's *effects*, not its decisions: what actually reaches a notification centre, from
/// which process, and when authorization is asked for.
///
/// **Why this suite exists.** `CompletionAlarmTests` covers `CompletionAlarm.decision`
/// thoroughly, and that turned out to fence almost nothing about the alarm the user
/// experiences. Three mutations against `CompletionScheduler` and its callers each left
/// the whole suite green: deleting the widget path's `scheduler?.reconcile` — which
/// removes the alarm for every widget press, every `cadence://` command and every
/// Shortcuts invocation, precisely the app-quit case D3 was amended for — making
/// `.cancel` a no-op, and flipping the observation path's `arming: false` to `true`. The
/// decision function was right the whole time and nothing armed anything.
///
/// The reason no test could see it was the seam: `center` was typed as
/// `UNUserNotificationCenter?`, so the only injectable value was `nil`. It is now
/// `any CompletionCentre`, and this suite injects a double that records every call.
final class CompletionSchedulerTests: XCTestCase {
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

    /// A fresh scheduler over a fresh centre. Fresh matters: `hasRequested` is per
    /// instance, and "authorization is asked for once" is one of the things under test.
    private func scheduler() -> (CompletionScheduler, RecordingCentre) {
        let centre = RecordingCentre()
        return (CompletionScheduler(center: { centre }), centre)
    }

    // MARK: - Arming

    /// The three edges D3 schedules on, through the whole path rather than to the
    /// decision: one request, under the one stable identifier, with a trigger that fires
    /// at the record's own deadline.
    ///
    /// The interval is asserted rather than the deadline, because that is what the
    /// framework is actually given — the deadline is an instant and
    /// `UNTimeIntervalNotificationTrigger` counts from now, which is the property that
    /// makes a session survive a clock change (§7).
    func testTheThreeSchedulingEdgesArmARequestAtTheirOwnDeadline() throws {
        let start = Clock.at(13, 48)
        let started = SessionTransitions.start(.idle(), duration: 25 * minute, now: start)

        let paused = SessionTransitions.pause(started, now: Clock.at(13, 58))
        let resumed = SessionTransitions.resume(paused, now: Clock.at(14, 3))

        let completed = SessionTransitions.reconciled(started, now: Clock.at(14, 13))
        let extended = SessionTransitions.extend(completed, now: Clock.at(14, 14))

        for (label, state, now, interval) in [
            ("start", started, start, 25 * minute),
            ("resume", resumed, Clock.at(14, 3), 15 * minute),
            ("extend", extended, Clock.at(14, 14), 5 * minute),
        ] {
            let (scheduler, centre) = scheduler()
            scheduler.reconcile(with: state, now: now)

            XCTAssertEqual(centre.added.count, 1, "\(label) arms exactly one request")
            XCTAssertEqual(
                centre.added.first?.identifier, CompletionAlarm.identifier,
                "\(label) arms under the one identifier that makes arming idempotent"
            )
            XCTAssertEqual(
                try XCTUnwrap(centre.added.first?.interval), interval, accuracy: 0.001,
                "\(label) arms its own deadline"
            )
            XCTAssertEqual(centre.removedPending, [], "\(label) is an arm, not a cancel")
        }
    }

    /// The banner's copy reaches the centre, not just `CompletionAlarm.text`.
    func testTheArmedRequestCarriesTheSessionsOwnCopyAndGrouping() {
        var state = SessionTransitions.start(.idle(), duration: 25 * minute, now: Clock.at(13, 48))
        state.title = "Design review"

        let (scheduler, centre) = scheduler()
        scheduler.reconcile(with: state, now: Clock.at(13, 48))

        let request = centre.added.first
        XCTAssertEqual(request?.title, "Session complete")
        XCTAssertEqual(request?.body, "Design review")
        XCTAssertEqual(
            request?.threadIdentifier, CompletionAlarm.threadIdentifier,
            "two stores' banners have to read as one session"
        )
    }

    /// Arming twice in a row is one pending request, because the identifier is stable —
    /// which is the property that lets every write path call `reconcile` unconditionally.
    func testReArmingReplacesRatherThanAccumulates() {
        let now = Clock.at(13, 48)
        let started = SessionTransitions.start(.idle(), duration: 25 * minute, now: now)

        let (scheduler, centre) = scheduler()
        scheduler.reconcile(with: started, now: now)
        scheduler.reconcile(with: started, now: now)

        XCTAssertEqual(centre.added.map(\.identifier), [CompletionAlarm.identifier, CompletionAlarm.identifier])
        XCTAssertEqual(
            Set(centre.added.map(\.identifier)).count, 1,
            "both requests are the same identifier, so the store holds one"
        )
    }

    // MARK: - Cancelling

    /// `pause` and `reset` remove, and so do the two states that are not a session and
    /// the running-but-elapsed record. Delivered notifications go with the pending one: a
    /// banner still sitting in Notification Center for a session the user has since
    /// paused is the same lie as an armed alarm.
    func testEveryStateThatIsNotALiveDeadlineRemovesTheRequest() {
        let started = SessionTransitions.start(.idle(), duration: 25 * minute, now: Clock.at(13, 48))
        let elapsed = SessionState.running(
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            segmentStartedAt: Clock.at(13, 48)
        )

        for (label, state, now) in [
            ("pause", SessionTransitions.pause(started, now: Clock.at(13, 58)), Clock.at(13, 58)),
            ("reset", SessionTransitions.reset(started, now: Clock.at(13, 58)), Clock.at(13, 58)),
            ("idle", SessionState.idle(), Clock.at(13, 58)),
            ("complete", SessionTransitions.reconciled(started, now: Clock.at(14, 13)), Clock.at(14, 13)),
            ("running past its deadline", elapsed, Clock.at(14, 20)),
        ] {
            let (scheduler, centre) = scheduler()
            scheduler.reconcile(with: state, now: now)

            XCTAssertEqual(
                centre.removedPending, [[CompletionAlarm.identifier]],
                "\(label) removes the pending request"
            )
            XCTAssertEqual(
                centre.removedDelivered, [[CompletionAlarm.identifier]],
                "\(label) clears a banner already delivered for it"
            )
            XCTAssertEqual(centre.added, [], "\(label) holds no alarm to arm")
        }
    }

    // MARK: - The observation asymmetry

    /// `arming: false` is the app re-reading a record *another* process wrote — on wake,
    /// on activation, on a KVO notification. It must still cancel, because a widget
    /// `pause` leaves the app's alarm armed at a stopped session and only the app can
    /// reach it. It must not arm, because the process that performed the transition
    /// already armed its own and a second one here is D3's avoidable duplicate.
    ///
    /// This is the assertion the old `testTheObservationPathCancelsWithoutArming` did not
    /// make: it checked `CompletionAlarm.decision`, which is identical whatever `arming`
    /// is, so flipping the flag changed nothing it looked at.
    func testTheObservationPathCancelsButNeverArms() {
        let now = Clock.at(13, 48)
        let started = SessionTransitions.start(.idle(), duration: 25 * minute, now: now)

        let (observing, observingCentre) = scheduler()
        observing.reconcile(with: started, now: now, arming: false)
        XCTAssertEqual(
            observingCentre.added, [],
            "an observation must not arm a second alarm for a session whose writer armed one"
        )
        XCTAssertEqual(
            observingCentre.removedPending, [],
            "and it must not cancel the one that is legitimately armed either"
        )

        // The same call over a record that has stopped: now it is the cancel only this
        // side can perform.
        let (cancelling, cancellingCentre) = scheduler()
        cancelling.reconcile(
            with: SessionTransitions.pause(started, now: Clock.at(13, 58)),
            now: Clock.at(13, 58),
            arming: false
        )
        XCTAssertEqual(cancellingCentre.removedPending, [[CompletionAlarm.identifier]])
        XCTAssertEqual(cancellingCentre.added, [])

        // And the writing path over the same live record does arm, which is what makes
        // the flag an asymmetry rather than a synonym.
        let (writing, writingCentre) = scheduler()
        writing.reconcile(with: started, now: now, arming: true)
        XCTAssertEqual(writingCentre.added.count, 1)
    }

    // MARK: - Authorization (D3)

    /// D3 moves the authorization request out of launch and into first schedule: a
    /// menu-bar app that prompts before the user has started anything is asking
    /// permission for a thing it has not been asked to do.
    ///
    /// So: nothing on construction, nothing on a reconcile that only cancels, one request
    /// on the first schedule, and the stored grant thereafter.
    func testAuthorizationIsAskedForOnceAndOnlyOnAFirstSchedule() {
        let now = Clock.at(13, 48)
        let started = SessionTransitions.start(.idle(), duration: 25 * minute, now: now)

        let (scheduler, centre) = scheduler()
        XCTAssertEqual(
            centre.authorizationRequests, 0,
            "constructing a scheduler is not a schedule, and launch must not prompt"
        )

        scheduler.reconcile(with: SessionState.idle(), now: now)
        XCTAssertEqual(
            centre.authorizationRequests, 0,
            "cancelling needs no permission, so it must not raise the prompt"
        )

        scheduler.reconcile(with: started, now: now)
        XCTAssertEqual(centre.authorizationRequests, 1, "the first schedule asks")
        XCTAssertEqual(centre.statusReads, 0)
        XCTAssertEqual(centre.added.count, 1)

        scheduler.reconcile(with: started, now: now)
        XCTAssertEqual(
            centre.authorizationRequests, 1,
            "every later schedule answers from the stored grant instead"
        )
        XCTAssertEqual(centre.statusReads, 1)
        XCTAssertEqual(centre.added.count, 2)
    }

    /// A refused grant arms nothing. `.provisional` counts as granted on the stored-grant
    /// path, because a quiet completion alarm is still an audible one when it fires.
    func testARefusedGrantArmsNothing() {
        let now = Clock.at(13, 48)
        let started = SessionTransitions.start(.idle(), duration: 25 * minute, now: now)

        let centre = RecordingCentre()
        centre.grant = false
        centre.status = .denied
        let scheduler = CompletionScheduler(center: { centre })

        scheduler.reconcile(with: started, now: now)
        XCTAssertEqual(centre.added, [], "an ungranted first schedule arms nothing")

        scheduler.reconcile(with: started, now: now)
        XCTAssertEqual(centre.added, [], "and neither does a denied stored grant")
    }

    // MARK: - No centre

    /// The configuration the suite and any process LaunchServices does not know both run
    /// in: `UNUserNotificationCenter.current()` throws `bundleProxyForCurrentProcess is
    /// nil`, so the injected closure hands back `nil` and every branch has to be inert
    /// rather than crash.
    ///
    /// The old version of this test made no assertions at all. There is nothing to assert
    /// *about* a nil centre except that both branches survive it, so what it now pins is
    /// that the record is untouched either way — a scheduler with nowhere to arm must not
    /// take it out on the container.
    func testASchedulerWithoutACentreIsInertRatherThanBroken() {
        let now = Clock.at(13, 48)
        let started = SessionTransitions.start(.idle(), duration: 25 * minute, now: now)
        let scheduler = CompletionScheduler(center: { nil })

        store.save(started)
        scheduler.reconcile(with: started, now: now)
        scheduler.reconcile(with: SessionState.idle(), now: now)
        scheduler.reconcile(with: started, now: now, arming: false)
        scheduler.reconcile(with: store, now: now)

        XCTAssertEqual(
            store.loadStoredSessionState(), started,
            "the scheduler reads the record and never writes it"
        )
    }

    // MARK: - The container overload

    /// The overload that reads the container is the one a caller who has just written
    /// should reach for, because the container is authoritative (P2). It has to arm the
    /// same alarm the state-taking one does.
    func testTheContainerOverloadArmsWhatTheStoredRecordImplies() throws {
        let now = Clock.at(13, 48)
        store.save(SessionTransitions.start(.idle(), duration: 25 * minute, now: now))

        let (scheduler, centre) = scheduler()
        scheduler.reconcile(with: store, now: now)

        XCTAssertEqual(centre.added.count, 1)
        XCTAssertEqual(try XCTUnwrap(centre.added.first?.interval), 25 * minute, accuracy: 0.001)
    }
}

// MARK: - The double

/// Records the five calls `CompletionCentre` declares and answers them synchronously.
///
/// Synchronously on purpose: the framework's handlers are asynchronous, but nothing in
/// `CompletionScheduler` depends on that, and a double that calls back inline turns every
/// assertion here into a straight-line one rather than an expectation with a timeout. The
/// lock is because the protocol's handlers are `@Sendable` and the compiler is right to
/// insist even when this instance never leaves the test's thread.
final class RecordingCentre: CompletionCentre, @unchecked Sendable {

    /// What a request looked like by the time it reached the centre — flattened, because
    /// `UNNotificationRequest` is not `Equatable` and the fields that matter are few.
    struct Request: Equatable {
        var identifier: String
        var title: String
        var body: String
        var threadIdentifier: String
        /// The trigger's interval. `nil` for a request with no interval trigger, which
        /// would itself be a defect — the deadline is an instant, not a wall-clock time.
        var interval: TimeInterval?
    }

    private let lock = NSLock()
    private var storage = Storage()

    private struct Storage {
        var added: [Request] = []
        var removedPending: [[String]] = []
        var removedDelivered: [[String]] = []
        var authorizationRequests = 0
        var statusReads = 0
        var grant = true
        var status: UNAuthorizationStatus = .authorized
    }

    private func read<T>(_ body: (Storage) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(storage)
    }

    private func write<T>(_ body: (inout Storage) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&storage)
    }

    var added: [Request] { read { $0.added } }
    var removedPending: [[String]] { read { $0.removedPending } }
    var removedDelivered: [[String]] { read { $0.removedDelivered } }
    var authorizationRequests: Int { read { $0.authorizationRequests } }
    var statusReads: Int { read { $0.statusReads } }

    /// What `requestAuthorization` answers on the first ask.
    var grant: Bool {
        get { read { $0.grant } }
        set { write { $0.grant = newValue } }
    }

    /// What the stored-grant path answers on every later one.
    var status: UNAuthorizationStatus {
        get { read { $0.status } }
        set { write { $0.status = newValue } }
    }

    // MARK: CompletionCentre

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)?
    ) {
        let interval = (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
        write {
            $0.added.append(Request(
                identifier: request.identifier,
                title: request.content.title,
                body: request.content.body,
                threadIdentifier: request.content.threadIdentifier,
                interval: interval
            ))
        }
        completionHandler?(nil)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        write { $0.removedPending.append(identifiers) }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        write { $0.removedDelivered.append(identifiers) }
    }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void
    ) {
        let granted = write { storage -> Bool in
            storage.authorizationRequests += 1
            return storage.grant
        }
        completionHandler(granted, nil)
    }

    func currentAuthorizationStatus(
        _ completionHandler: @escaping @Sendable (UNAuthorizationStatus) -> Void
    ) {
        let status = write { storage -> UNAuthorizationStatus in
            storage.statusReads += 1
            return storage.status
        }
        completionHandler(status)
    }
}
