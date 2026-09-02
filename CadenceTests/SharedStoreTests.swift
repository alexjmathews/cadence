import XCTest
@testable import Cadence

/// Staleness, corruption, and failure behaviour, against a scratch suite so a test
/// run cannot scribble on the session the developer is actually using. The four
/// round-trips go through the real container instead — see `AppGroupRoundTripTests`.
final class SharedStoreTests: XCTestCase {
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

    /// `removePersistentDomain` empties the domain but leaves the plist behind, so
    /// the file goes too.
    private func clearScratchSuite() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let plist = URL.homeDirectory
            .appending(path: "Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    func testProductionStoreUsesTheDocumentedAppGroupAndKeys() {
        XCTAssertEqual(SharedStore.appGroupID, "group.com.alexmathews.cadence")
        XCTAssertEqual(SharedStore.Key.sessionState, "sessionState")
        XCTAssertEqual(SharedStore.Key.preferences, "preferences")
        XCTAssertEqual(SharedStore.Key.dismissedEvents, "dismissedEvents")
        XCTAssertEqual(SharedStore.Key.calendarSnapshot, "calendarSnapshot")
    }

    // MARK: - Defaults, staleness, corruption

    func testMissingRecordsReadAsDefaults() {
        let now = Clock.at(14, 0)

        XCTAssertEqual(store.loadSessionState(now: now), SessionState())
        XCTAssertEqual(store.loadPreferences(), Preferences())
        XCTAssertEqual(
            store.loadDismissedEvents(now: now, calendar: Clock.calendar),
            DismissedEvents(day: Clock.startOfDay(now))
        )
        XCTAssertNil(store.loadCalendarSnapshot(now: now, calendar: Clock.calendar))
    }

    func testCorruptRecordsReadAsDefaultsRatherThanFailing() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(Data("not json".utf8), forKey: SharedStore.Key.sessionState)
        defaults.set(Data("not json".utf8), forKey: SharedStore.Key.calendarSnapshot)

        XCTAssertEqual(store.loadSessionState(now: Clock.at(14, 0)), SessionState())
        XCTAssertNil(store.loadCalendarSnapshot(now: Clock.at(14, 0), calendar: Clock.calendar))
    }

    func testStaleDayScopedRecordsAreDiscardedWholesale() {
        let yesterday = Clock.on(day: 3, 14, 0)
        let today = Clock.at(9, 0)

        XCTAssertTrue(store.save(DismissedEvents(day: Clock.startOfDay(yesterday), keys: ["standup|1"])))
        XCTAssertTrue(store.save(CalendarSnapshot(
            day: Clock.startOfDay(yesterday),
            events: [],
            lastSyncedAt: yesterday,
            access: .authorized
        )))

        XCTAssertEqual(
            store.loadDismissedEvents(now: today, calendar: Clock.calendar),
            DismissedEvents(day: Clock.startOfDay(today)),
            "a stale set is discarded, not pruned key by key"
        )
        XCTAssertNil(store.loadCalendarSnapshot(now: today, calendar: Clock.calendar))
    }

    func testSessionStateIsReconciledOnLoad() {
        let state = SessionState.running(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            segmentStartedAt: Clock.at(13, 48)
        )
        XCTAssertTrue(store.save(state))

        let loaded = store.loadSessionState(now: Clock.at(16, 30))

        XCTAssertEqual(loaded.status, .complete, "a session that elapsed while quit loads complete")
        XCTAssertEqual(loaded.completedAt, Clock.at(14, 13))
        XCTAssertEqual(loaded.focusedBefore, 25 * minute)
    }

    func testRevokedAccessCanClearTheSnapshot() {
        let now = Clock.at(14, 0)
        XCTAssertTrue(store.save(CalendarSnapshot(
            day: Clock.startOfDay(now),
            events: [],
            lastSyncedAt: now,
            access: .authorized
        )))

        XCTAssertTrue(store.removeCalendarSnapshot())
        XCTAssertNil(store.loadCalendarSnapshot(now: now, calendar: Clock.calendar))
    }

    // MARK: - Day scoping follows the system time zone

    /// The app runs for weeks while the widget process is respawned constantly. A
    /// `Calendar` captured once would leave the two disagreeing about which day a
    /// record belongs to after a DST flip or a flight — one showing today's events
    /// while the other discarded them as stale.
    func testDayScopingFollowsATimeZoneChangeRatherThanASnapshot() {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }

        // 23:30 in New York is already the next day in UTC.
        let now = Clock.at(23, 30)

        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        let recorded = DismissedEvents(
            day: Calendar.autoupdatingCurrent.startOfDay(for: now),
            keys: ["standup|1"]
        )
        XCTAssertTrue(store.save(recorded))
        XCTAssertEqual(store.loadDismissedEvents(now: now), recorded, "fresh in the zone it was written in")

        NSTimeZone.default = TimeZone(identifier: "UTC")!
        let reread = store.loadDismissedEvents(now: now)

        XCTAssertEqual(
            reread.day,
            Calendar.autoupdatingCurrent.startOfDay(for: now),
            "the day is recomputed in the zone the process is now in"
        )
        XCTAssertNotEqual(reread.day, recorded.day)
        XCTAssertTrue(reread.keys.isEmpty, "and yesterday's dismissals are discarded")
    }

    // MARK: - Failure reporting

    func testAWriteToAnUnresolvableSuiteIsReportedRatherThanDropped() {
        // `UserDefaults(suiteName:)` rejects the global domain, which is the one
        // reachable stand-in for a suite that cannot resolve.
        XCTAssertNil(UserDefaults(suiteName: UserDefaults.globalDomain), "precondition: the suite must be unresolvable")

        let unusable = SharedStore(suiteName: UserDefaults.globalDomain, reloadsWidgets: false)

        XCTAssertFalse(unusable.save(Preferences(endEarlyBuffer: 60, lastUsedDuration: 60)))
        XCTAssertFalse(unusable.save(SessionState()))
        XCTAssertFalse(unusable.removeCalendarSnapshot())
    }
}
