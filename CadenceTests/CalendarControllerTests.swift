import XCTest
@testable import Cadence

/// The app-layer calendar controller: the three access states end to end, revocation
/// clearing the snapshot, dismissals through the container, and the exit criteria that
/// a refresh and a buffer change never retime a running session.
///
/// Against a scratch suite and the fixture seam, so a test run can neither scribble on
/// the session the developer is using nor depend on what is in their calendar.
@MainActor
final class CalendarControllerTests: XCTestCase {
    nonisolated private static let suiteName = "group.com.alexmathews.cadence.tests"

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

    /// A fixed afternoon on the *real* calendar's terms, because the controller reads
    /// its day boundaries from the injected `Calendar` and the tests inject `Clock`'s.
    private let now = Clock.at(14, 13)

    /// A controller whose launch refresh has already landed.
    ///
    /// The fetch is off the main actor now (Apple's guidance is not to enumerate an
    /// `EKEventStore` on it), so `init` starts it rather than waiting on it and the
    /// suite awaits the same handle a caller would.
    private func controller(
        _ events: FixtureEventStore,
        now: Date? = nil
    ) async -> CalendarController {
        let controller = CalendarController(
            store: store,
            events: events,
            calendar: Clock.calendar,
            now: now ?? self.now,
            observesSystem: false
        )
        await controller.refreshTask?.value
        return controller
    }

    private var today: [CalendarEventRecord] {
        [
            .timed("review", "Review", from: Clock.at(15, 30), colorHex: "FF8A3D"),
            .timed("oneToOne", "One to one", from: Clock.at(16, 15), colorHex: "2F6BFF"),
            .timed("notes", "Notes", from: Clock.at(17, 0), colorHex: "2FE0A6"),
        ]
    }

    private func key(_ identifier: String, _ startsAt: Date) -> String {
        EventOccurrence.makeID(eventIdentifier: identifier, startsAt: startsAt)
    }

    // MARK: - The three access states

    func testAnUndeterminedCalendarFetchesNothingAndStoresNothing() async {
        let events = FixtureEventStore(access: .notDetermined, records: today)

        let calendar = await controller(events)

        XCTAssertEqual(calendar.access, .notDetermined)
        XCTAssertNil(calendar.snapshot(at: now))
        XCTAssertEqual(events.fetchCount, 0, "nothing is read from behind a gate that has not opened")
        XCTAssertNil(store.loadCalendarSnapshot(now: now, calendar: Clock.calendar))
    }

    func testConnectingPromptsOnceAndThenFetches() async {
        let events = FixtureEventStore(access: .notDetermined, records: today)
        let calendar = await controller(events)

        await calendar.connect(now: { self.now })

        XCTAssertEqual(calendar.access, .authorized)
        XCTAssertEqual(calendar.snapshot(at: now)?.events.count, 3)
    }

    /// The permission sheet can sit unanswered for minutes, so the instant the refresh
    /// is stamped with has to be read *after* the prompt returns — a `now` captured at
    /// the press can belong to a day that is no longer the current one.
    func testConnectReadsTheClockAfterThePrompt() async {
        let events = FixtureEventStore(access: .notDetermined, records: today)
        let calendar = await controller(events)
        var readWhilePrompting: Bool?

        await calendar.connect(now: {
            readWhilePrompting = !events.didPrompt
            return self.now
        })

        XCTAssertEqual(readWhilePrompting, false, "the clock is read after the prompt, not before it")
    }

    func testADeniedCalendarShowsNothing() async {
        let calendar = await controller(FixtureEventStore(access: .denied, records: today))

        XCTAssertEqual(calendar.access, .denied)
        XCTAssertNil(calendar.snapshot(at: now))
    }

    func testAnAuthorizedCalendarWritesTodayIntoTheContainer() async throws {
        let calendar = await controller(FixtureEventStore(records: today))

        let stored = try XCTUnwrap(store.loadCalendarSnapshot(now: now, calendar: Clock.calendar))

        XCTAssertEqual(stored, calendar.snapshot(at: now))
        XCTAssertEqual(stored.events.map(\.title), ["Review", "One to one", "Notes"])
        XCTAssertEqual(stored.access, .authorized)
        XCTAssertEqual(stored.day, Clock.startOfDay(now))
    }

    /// The exit criterion. Revocation is not a special path: access is read first on
    /// every refresh, and anything short of authorized removes the record so no
    /// surface — including a widget the app cannot see — can render stale events.
    func testRevocationClearsTheStoredSnapshot() async {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)
        XCTAssertNotNil(store.loadCalendarSnapshot(now: now, calendar: Clock.calendar))

        events.stubbedAccess = .denied
        await calendar.refresh(now: now)

        XCTAssertEqual(calendar.access, .denied)
        XCTAssertNil(calendar.snapshot(at: now))
        XCTAssertNil(
            store.loadCalendarSnapshot(now: now, calendar: Clock.calendar),
            "stale events must not outlive the permission that fetched them"
        )
    }

    // MARK: - Dismissals

    func testDismissingWritesADayScopedRecordAndPromotesTheNextEvent() async {
        let calendar = await controller(FixtureEventStore(records: today))
        let review = key("review", Clock.at(15, 30))

        XCTAssertEqual(calendar.suggestion(buffer: 2 * minute, now: now)?.title, "Review")

        calendar.dismiss(review, now: now)

        XCTAssertEqual(calendar.dismissed, [review])
        XCTAssertEqual(calendar.suggestion(buffer: 2 * minute, now: now)?.title, "One to one")
        XCTAssertEqual(
            store.loadDismissedEvents(now: now, calendar: Clock.calendar),
            DismissedEvents(day: Clock.startOfDay(now), keys: [review])
        )
    }

    func testRestoringPutsTheEventBack() async {
        let calendar = await controller(FixtureEventStore(records: today))
        let review = key("review", Clock.at(15, 30))

        calendar.dismiss(review, now: now)
        calendar.restore(review, now: now)

        XCTAssertTrue(calendar.dismissed.isEmpty)
        XCTAssertEqual(calendar.suggestion(buffer: 2 * minute, now: now)?.title, "Review")
    }

    /// §2.4: the whole record is day-scoped, so yesterday's dismissals are discarded
    /// wholesale rather than pruned key by key.
    func testYesterdaysDismissalsAreDiscardedWholesale() async {
        let yesterday = Clock.on(day: 3, 14, 13)
        XCTAssertTrue(
            store.save(
                DismissedEvents(
                    day: Clock.startOfDay(yesterday),
                    keys: [key("review", Clock.at(15, 30))]
                )
            )
        )

        let calendar = await controller(FixtureEventStore(records: today))

        XCTAssertTrue(calendar.dismissed.isEmpty)
        XCTAssertEqual(calendar.suggestion(buffer: 2 * minute, now: now)?.title, "Review")
    }

    /// A refresh rewrites `calendarSnapshot` only, which is why it cannot clobber a
    /// dismissal written between the two (§2.4).
    func testARefreshPreservesDismissals() async {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)
        let review = key("review", Clock.at(15, 30))

        calendar.dismiss(review, now: now)
        await calendar.refresh(now: now)

        XCTAssertEqual(calendar.dismissed, [review])
        XCTAssertEqual(calendar.suggestion(buffer: 2 * minute, now: now)?.title, "One to one")
    }

    // MARK: - Meeting-linked start (P4)

    func testAMeetingStartMaterialisesTheBufferedDeadlineFromTheLiveStore() async throws {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)
        let before = events.fetchCount

        let resolved = await calendar.meetingStart(
            for: key("review", Clock.at(15, 30)),
            buffer: 2 * minute,
            now: now
        )
        let meeting = try XCTUnwrap(resolved)

        XCTAssertEqual(meeting.title, "Review")
        XCTAssertEqual(meeting.endsAt, Clock.at(15, 28), "eventStart − buffer")
        XCTAssertEqual(meeting.key, key("review", Clock.at(15, 30)))
        XCTAssertGreaterThan(
            events.fetchCount, before,
            "the key is re-resolved against the live store, not read out of the snapshot"
        )
    }

    /// The recurring-identifier risk, end to end: a key the store no longer agrees with
    /// fails as "no suggestion", never as a wrong timer.
    func testAStaleKeyStartsNothing() async {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)

        events.records = []

        let resolved = await calendar.meetingStart(for: key("review", Clock.at(15, 30)), buffer: 2 * minute, now: now)
        XCTAssertNil(resolved)
    }

    /// An event moved since the snapshot is a *different* occurrence, so the composite
    /// key declines rather than quietly retiming the session to the new start.
    func testAnEventMovedSinceTheSnapshotStartsNothing() async {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)

        events.records = [.timed("review", "Review", from: Clock.at(16, 45))]

        let resolved = await calendar.meetingStart(for: key("review", Clock.at(15, 30)), buffer: 2 * minute, now: now)
        XCTAssertNil(resolved)
    }

    func testAMeetingTheBufferHasEatenStartsNothing() async {
        let events = FixtureEventStore(
            records: [.timed("soon", "Soon", from: Clock.at(14, 14))]
        )
        let calendar = await controller(events)

        let resolved = await calendar.meetingStart(for: key("soon", Clock.at(14, 14)), buffer: 2 * minute, now: now)
        XCTAssertNil(resolved)
    }

    func testARevokedCalendarStartsNothing() async {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)
        events.stubbedAccess = .denied

        let resolved = await calendar.meetingStart(for: key("review", Clock.at(15, 30)), buffer: 2 * minute, now: now)
        XCTAssertNil(resolved)
    }

    // MARK: - Exit criteria against a running session

    /// "A refresh mid-session never retimes the running session." The controller writes
    /// two day-scoped keys and never `sessionState`; there is no path from a refresh to
    /// a deadline.
    func testARefreshMidSessionNeverRetimesTheSession() async {
        let session = SessionController(store: store, now: Date())
        session.selectDuration(25 * minute)
        session.start()
        let running = session.state

        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)
        events.records.append(.timed("extra", "Extra", from: Clock.at(15, 0)))
        await calendar.refresh(now: now)
        calendar.dismiss(key("review", Clock.at(15, 30)), now: now)
        session.refresh()

        XCTAssertEqual(session.state.endsAt, running.endsAt)
        XCTAssertEqual(session.state, running)
    }

    /// "Changing the buffer mid-session never retimes it either" (§2.2): the buffer is
    /// materialised into `endsAt` at start, so it has nothing left to act on.
    func testChangingTheBufferMidSessionNeverRetimesTheSession() async {
        let session = SessionController(store: store, now: Date())
        session.setBuffer(2 * minute)
        session.start()
        let running = session.state

        session.setBuffer(3 * minute)

        XCTAssertEqual(session.preferences.endEarlyBuffer, 3 * minute)
        XCTAssertEqual(session.state.endsAt, running.endsAt)
        XCTAssertEqual(session.state, running)
    }

    /// "A meeting timer started from the dropdown and from the window produce identical
    /// state." Both surfaces resolve through the one `meetingStart(for:buffer:)`, so the
    /// state they hand the session is the same value — not two values that happen to
    /// agree.
    func testTheWindowAndTheDropdownResolveTheSameMeetingStart() async throws {
        let calendar = await controller(FixtureEventStore(records: today))
        let occurrence = key("review", Clock.at(15, 30))

        // The window strip's path, and the dropdown row's: one derivation, two callers.
        let window = await calendar.meetingStart(for: occurrence, buffer: 2 * minute, now: now)
        let dropdown = await calendar.meetingStart(for: occurrence, buffer: 2 * minute, now: now)
        let fromWindow = try XCTUnwrap(window)
        let fromDropdown = try XCTUnwrap(dropdown)

        XCTAssertEqual(fromWindow, fromDropdown)
        XCTAssertEqual(fromWindow.endsAt, Clock.at(15, 28), "eventStart − buffer (P4)")
        XCTAssertEqual(fromWindow.title, "Review")
        XCTAssertEqual(fromWindow.key, occurrence)
    }

    /// The other half: applying one resolved `MeetingStart` copies the title, records
    /// the key as provenance, and lands the deadline exactly on the buffered instant —
    /// not on "now plus a duration computed a moment earlier".
    func testStartingAMeetingCopiesTheTitleTheDeadlineAndTheKey() async {
        let session = SessionController(store: store, now: Date())
        let meeting = MeetingStart(
            key: "review|1",
            title: "Review",
            endsAt: Date().addingTimeInterval(75 * minute)
        )

        session.startMeeting(meeting)

        XCTAssertEqual(session.state.status, .running)
        XCTAssertEqual(session.state.title, "Review")
        XCTAssertEqual(session.state.linkedEventKey, "review|1")
        XCTAssertEqual(session.state.endsAt, meeting.endsAt)
        assertInvariants(session.state)
    }

    /// Two surfaces, one `MeetingStart`, identical state — the deadline is not derived
    /// from which microsecond the press landed on.
    func testTwoSurfacesStartingTheSameMeetingProduceIdenticalState() async {
        let meeting = MeetingStart(
            key: "review|1",
            title: "Review",
            endsAt: Date().addingTimeInterval(75 * minute)
        )

        let window = SessionController(store: store, now: Date())
        window.startMeeting(meeting)
        let fromWindow = window.state
        window.reset()

        let dropdown = SessionController(store: store, now: Date())
        dropdown.startMeeting(meeting)
        let fromDropdown = dropdown.state

        XCTAssertEqual(fromWindow.title, fromDropdown.title)
        XCTAssertEqual(fromWindow.linkedEventKey, fromDropdown.linkedEventKey)
        XCTAssertEqual(fromWindow.endsAt, fromDropdown.endsAt)
        XCTAssertEqual(fromWindow.endsAt, meeting.endsAt)
    }

    /// P4: the session copies a title and a deadline, never a pointer. Once it is
    /// running, the event disappearing from under it changes nothing.
    func testARunningMeetingSessionSurvivesTheEventDisappearing() async {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)
        let session = SessionController(store: store, now: Date())

        session.startMeeting(
            MeetingStart(
                key: key("review", Clock.at(15, 30)),
                title: "Review",
                endsAt: Date().addingTimeInterval(75 * minute)
            )
        )
        let running = session.state

        events.records = []
        await calendar.refresh(now: now)
        session.refresh()

        XCTAssertEqual(session.state, running)
        XCTAssertEqual(session.state.title, "Review")
        XCTAssertNil(calendar.suggestion(buffer: 2 * minute, now: now))
    }

    /// §5: `start` is legal only from `idle` and `complete`, and a meeting start is a
    /// `start`. A second timer stays unstartable however it is asked for.
    func testAMeetingStartCannotStartASecondTimer() async {
        let session = SessionController(store: store, now: Date())
        session.selectDuration(25 * minute)
        session.start()
        let running = session.state

        session.startMeeting(
            MeetingStart(
                key: "review|1",
                title: "Review",
                endsAt: Date().addingTimeInterval(75 * minute)
            )
        )

        XCTAssertEqual(session.state, running)
    }

    /// A `MeetingStart` whose deadline has passed between the press and the write —
    /// the machine slept, or the buffer moved under it — starts nothing rather than a
    /// session that is already over.
    func testAnElapsedMeetingStartIsRefused() async {
        let session = SessionController(store: store, now: Date())
        let idle = session.state

        session.startMeeting(
            MeetingStart(key: "stale|1", title: "Stale", endsAt: Date().addingTimeInterval(-60))
        )

        XCTAssertEqual(session.state, idle)
    }

    // MARK: - Freshness at the read (§2.3, §4)

    /// The window can be open and frontmost across midnight: no calendar edit, no
    /// activation, no wake — and so, before this, no refresh. `snapshot(at:)` is where
    /// "never yesterday's meetings" is enforced for every surface at once.
    func testTheSnapshotIsGatedOnTheDayItIsReadFor() async {
        let calendar = await controller(FixtureEventStore(records: today))
        let afterMidnight = Clock.on(day: 5, 0, 5)

        XCTAssertNotNil(calendar.snapshot(at: now))
        XCTAssertNotNil(calendar.storedSnapshot, "the record is still in hand")
        XCTAssertNil(
            calendar.snapshot(at: afterMidnight),
            "it is simply not this day's snapshot"
        )
        XCTAssertNil(calendar.suggestion(buffer: 2 * minute, now: afterMidnight))
    }

    /// And the gate is not a substitute for refreshing: once the rollover is noticed,
    /// the day's own events are read and the snapshot is today's again.
    func testARefreshAfterMidnightRestampsTheSnapshot() async {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)
        let tomorrow = Clock.on(day: 5, 9, 0)
        events.records = [.timed("standup", "Standup", from: Clock.on(day: 5, 10, 0))]

        await calendar.refresh(now: tomorrow)

        XCTAssertEqual(calendar.snapshot(at: tomorrow)?.day, Clock.startOfDay(tomorrow))
        XCTAssertEqual(calendar.snapshot(at: tomorrow)?.events.count, 1)
    }

    // MARK: - Dismissals across a rollover

    /// §2.4's day-scoped container exists to make dismissal drift structurally
    /// impossible, and building the write from the *in-memory* set defeated it: keys
    /// belonging to yesterday were re-stamped with today's date. The write re-reads the
    /// container, which discards another day's record on read.
    func testADismissalDoesNotCarryYesterdaysKeysIntoTodaysRecord() async {
        let yesterday = Clock.on(day: 3, 14, 13)
        let events = FixtureEventStore(
            records: [.timed("standup", "Standup", from: Clock.on(day: 3, 15, 30))]
        )
        let calendar = await controller(events, now: yesterday)
        let yesterdaysKey = key("standup", Clock.on(day: 3, 15, 30))

        calendar.dismiss(yesterdaysKey, now: yesterday)
        XCTAssertEqual(calendar.dismissed, [yesterdaysKey])

        // The day rolls over with nothing refreshing, and then a dismissal happens.
        let todaysKey = key("review", Clock.at(15, 30))
        calendar.dismiss(todaysKey, now: now)

        XCTAssertEqual(calendar.dismissed, [todaysKey], "yesterday's key is gone, not re-stamped")
        XCTAssertEqual(
            store.loadDismissedEvents(now: now, calendar: Clock.calendar),
            DismissedEvents(day: Clock.startOfDay(now), keys: [todaysKey])
        )
    }

    /// The same discipline on the way back: `Undo hide` writes against the container's
    /// set, so it cannot resurrect a key the day boundary has already discarded.
    func testARestoreWritesAgainstTheContainersSet() async {
        let calendar = await controller(FixtureEventStore(records: today))
        let review = key("review", Clock.at(15, 30))
        let oneToOne = key("oneToOne", Clock.at(16, 15))

        calendar.dismiss(review, now: now)
        calendar.dismiss(oneToOne, now: now)
        calendar.restore(review, now: now)

        XCTAssertEqual(calendar.dismissed, [oneToOne])
        XCTAssertEqual(
            store.loadDismissedEvents(now: now, calendar: Clock.calendar).keys,
            [oneToOne]
        )
    }

    /// Revocation clears the dismissals too: they are keys into a day's events the app
    /// can no longer see, and keeping them would hide rows in whatever is fetched next.
    func testRevocationClearsTheDismissals() async {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)
        calendar.dismiss(key("review", Clock.at(15, 30)), now: now)

        events.stubbedAccess = .denied
        await calendar.refresh(now: now)

        XCTAssertTrue(calendar.dismissed.isEmpty)
    }

    // MARK: - A refresh that changed nothing writes nothing

    /// `lastSyncedAt: now` guarantees the record differs on every refresh, so every
    /// activation and every `EKEventStoreChanged` was writing the plist, reloading
    /// every widget timeline and firing `didChange` on the suite — which costs the
    /// session controller a re-read. A refresh that found the same day's same events
    /// now writes nothing at all.
    func testARefreshThatChangedNothingDoesNotRewriteTheRecord() async throws {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)
        let first = try XCTUnwrap(calendar.storedSnapshot?.lastSyncedAt)

        await calendar.refresh(now: now.addingTimeInterval(90))

        XCTAssertEqual(calendar.storedSnapshot?.lastSyncedAt, first, "nothing changed, so nothing was written")
        XCTAssertEqual(
            store.loadCalendarSnapshot(now: now, calendar: Clock.calendar)?.lastSyncedAt,
            first
        )
    }

    /// The other half — suppression must not swallow a real change.
    func testARefreshThatFoundAChangeWritesIt() async throws {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)
        let first = try XCTUnwrap(calendar.storedSnapshot?.lastSyncedAt)
        let later = now.addingTimeInterval(90)

        events.records.append(.timed("extra", "Extra", from: Clock.at(15, 0)))
        await calendar.refresh(now: later)

        XCTAssertEqual(calendar.storedSnapshot?.lastSyncedAt, later)
        XCTAssertNotEqual(calendar.storedSnapshot?.lastSyncedAt, first)
        XCTAssertEqual(calendar.snapshot(at: now)?.events.count, 4)
    }

    /// A day rollover is a change even when the events are identical, or the stale
    /// snapshot would keep yesterday's stamp and stay stale forever.
    func testARolloverIsAlwaysAWrite() async throws {
        let events = FixtureEventStore(records: today)
        let calendar = await controller(events)
        let tomorrow = Clock.on(day: 5, 14, 13)
        events.records = [.timed("review", "Review", from: Clock.on(day: 5, 15, 30))]

        await calendar.refresh(now: tomorrow)

        XCTAssertEqual(calendar.storedSnapshot?.day, Clock.startOfDay(tomorrow))
        XCTAssertEqual(calendar.storedSnapshot?.lastSyncedAt, tomorrow)
    }

    // MARK: - The fetch is off the main actor

    /// The seam's whole purpose after this change: `refresh` awaits the fetch rather
    /// than performing it inline, so `init` returns before the events are in. A caller
    /// that needs them awaits the handle.
    func testTheLaunchRefreshIsAwaitableRatherThanBlocking() async {
        let events = FixtureEventStore(records: today)
        let calendar = CalendarController(
            store: store,
            events: events,
            calendar: Clock.calendar,
            now: now,
            observesSystem: false
        )

        let task = calendar.refreshTask
        XCTAssertNotNil(task, "init starts the refresh rather than performing it")
        await task?.value

        XCTAssertEqual(calendar.snapshot(at: now)?.events.count, 3)
    }
}
