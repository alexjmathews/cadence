import XCTest
@testable import Cadence

/// The exit criterion proper: encode → App Group → decode is identity for all four
/// records, through `SharedStore.shared` and therefore through the real container
/// at `~/Library/Group Containers/group.com.alexmathews.cadence/`.
///
/// Hosted in the app, so the test process holds the App Group entitlement. A
/// typo'd group identifier or a missing `com.apple.security.application-groups`
/// entry fails here rather than at runtime as "the widget shows nothing".
///
/// This is the developer's live container, so every test puts back what it found.
/// Nothing is cleared up front — each test overwrites only the key it asserts on,
/// which keeps the window in which a crash could cost a real session as small as
/// the test body itself.
final class AppGroupRoundTripTests: XCTestCase {
    private var store: SharedStore!
    private var restore: [(key: String, data: Data?)] = []

    private static let allKeys = [
        SharedStore.Key.sessionState,
        SharedStore.Key.preferences,
        SharedStore.Key.dismissedEvents,
        SharedStore.Key.calendarSnapshot,
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: SharedStore.appGroupID),
            "the App Group suite must resolve — check the entitlement and the group identifier"
        )
        // Snapshot before anything is written; the unwrap above is the only step
        // that can throw, and it runs before any mutation.
        restore = Self.allKeys.map { ($0, defaults.data(forKey: $0)) }
        store = SharedStore(reloadsWidgets: false)
    }

    override func tearDown() {
        let defaults = UserDefaults(suiteName: SharedStore.appGroupID)
        for (key, data) in restore {
            if let data {
                defaults?.set(data, forKey: key)
            } else {
                defaults?.removeObject(forKey: key)
            }
        }
        restore = []
        store = nil
        super.tearDown()
    }

    /// Checks the write targets the group domain rather than a same-named domain in
    /// the process's own preferences directory — the failure mode that looks fine
    /// from inside the writer and leaves the widget reading nothing.
    ///
    /// What it cannot check is the bytes on disk: `cfprefsd` owns
    /// `Library/Preferences/<group>.plist` and flushes it lazily, and
    /// `UserDefaults.synchronize()` has not forced that for years. Asserting file
    /// contents here would pass or fail on timing. Cross-process visibility is not
    /// reachable either: entitlements are not inherited by child processes, so a
    /// spawned `defaults read group.com.alexmathews.cadence` reports "domain does
    /// not exist" no matter what this process wrote. The round-trips above, run in
    /// a host that holds the entitlement, are what carry the exit criterion.
    func testWritesGoToTheGroupDomainAndNotALookalike() throws {
        // Nil here means no group container at all. Note macOS also answers this
        // for unentitled unsandboxed callers, so it is a smoke check, not proof of
        // the entitlement.
        _ = try XCTUnwrap(
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID),
            "no group container for \(SharedStore.appGroupID)"
        )

        let sentinel = Preferences(endEarlyBuffer: Double(Int.random(in: 1000...9999)), lastUsedDuration: 60)
        XCTAssertTrue(store.save(sentinel))
        XCTAssertEqual(store.loadPreferences(), sentinel)

        let lookalike = URL.homeDirectory
            .appending(path: "Library/Preferences/\(SharedStore.appGroupID).plist")
        XCTAssertNil(
            NSDictionary(contentsOf: lookalike)?[SharedStore.Key.preferences],
            "the write went to \(lookalike.path) instead of the group domain — the widget cannot read that"
        )
    }

    func testSessionStateRoundTripsUnchanged() {
        let state = SessionState.running(
            plannedDuration: 45 * minute,
            title: "Draft the memo",
            linkedEventKey: "abc|1",
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 33),
            focusedBefore: 90,
            segmentStartedAt: Clock.at(13, 50)
        )

        XCTAssertTrue(store.save(state))
        XCTAssertEqual(store.loadSessionState(now: Clock.at(14, 0)), state)
    }

    func testPreferencesRoundTripUnchanged() {
        let preferences = Preferences(endEarlyBuffer: 180, lastUsedDuration: 45 * minute)

        XCTAssertTrue(store.save(preferences))
        XCTAssertEqual(store.loadPreferences(), preferences)
    }

    func testDismissedEventsRoundTripUnchanged() {
        let now = Clock.at(14, 0)
        let dismissed = DismissedEvents(day: Clock.startOfDay(now), keys: ["standup|1", "review|2"])

        XCTAssertTrue(store.save(dismissed))
        XCTAssertEqual(store.loadDismissedEvents(now: now, calendar: Clock.calendar), dismissed)
    }

    func testCalendarSnapshotRoundTripsUnchanged() {
        let now = Clock.at(14, 0)
        let snapshot = CalendarSnapshot(
            day: Clock.startOfDay(now),
            events: [
                EventOccurrence(
                    id: EventOccurrence.makeID(eventIdentifier: "standup", startsAt: Clock.at(15, 0)),
                    title: "Standup",
                    startsAt: Clock.at(15, 0),
                    endsAt: Clock.at(15, 15)
                )
            ],
            lastSyncedAt: Clock.at(13, 55),
            access: .authorized
        )

        XCTAssertTrue(store.save(snapshot))
        XCTAssertEqual(store.loadCalendarSnapshot(now: now, calendar: Clock.calendar), snapshot)
    }

    /// A second `SharedStore` stands in for the widget extension: the record is
    /// read back through a fresh handle on the same container, not a cached copy.
    func testASecondStoreReadsWhatTheFirstWrote() {
        let state = SessionState.running(
            title: "Draft the memo",
            startedAt: Clock.at(13, 48),
            endsAt: Clock.at(14, 13),
            segmentStartedAt: Clock.at(13, 48)
        )

        XCTAssertTrue(store.save(state))
        let reader = SharedStore(reloadsWidgets: false)

        XCTAssertEqual(reader.loadSessionState(now: Clock.at(14, 0)), state)
    }
}
