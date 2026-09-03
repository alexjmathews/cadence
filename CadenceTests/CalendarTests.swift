import XCTest
@testable import Cadence

/// A `CalendarEventReading` double: fixed access, fixed records, and a count of the
/// fetches so a test can prove that re-resolution actually went back to the store
/// rather than reading the snapshot it was handed.
///
/// This is the point of the seam (testing strategy §6): recurrence expansion, all-day
/// exclusion and the three access states are exercised against these fixtures, and
/// nothing in the suite depends on whatever is in the developer's real calendar.
final class FixtureEventStore: CalendarEventReading, @unchecked Sendable {
    var stubbedAccess: CalendarAccess
    var records: [CalendarEventRecord]
    var fetchCount = 0
    /// Whether `requestAccess()` has been through the prompt, so a test can prove
    /// what the controller reads *after* it.
    var didPrompt = false
    /// What `requestAccess()` grants, as the system prompt would.
    var grants: CalendarAccess = .authorized

    init(access: CalendarAccess = .authorized, records: [CalendarEventRecord] = []) {
        self.stubbedAccess = access
        self.records = records
    }

    var access: CalendarAccess { stubbedAccess }

    func requestAccess() async -> CalendarAccess {
        guard stubbedAccess == .notDetermined else { return stubbedAccess }
        stubbedAccess = grants
        didPrompt = true
        return stubbedAccess
    }

    func events(from start: Date, to end: Date) -> [CalendarEventRecord] {
        fetchCount += 1
        guard stubbedAccess == .authorized else { return [] }
        // The real predicate returns everything *overlapping* the window; the fixture
        // does the same so the builder's own filtering is what the tests measure.
        return records.filter { record in
            guard let recordStart = record.startDate else { return true }
            return recordStart < end && (record.endDate ?? recordStart) >= start
        }
    }
}

extension CalendarEventRecord {
    /// A timed event in one of the three calendar colors the day list is composed
    /// against (visual spec §1.2).
    static func timed(
        _ identifier: String,
        _ title: String,
        from startsAt: Date,
        minutes: Int = 30,
        colorHex: String? = "2F6BFF"
    ) -> CalendarEventRecord {
        CalendarEventRecord(
            eventIdentifier: identifier,
            title: title,
            startDate: startsAt,
            endDate: startsAt.addingTimeInterval(Double(minutes) * minute),
            colorHex: colorHex
        )
    }
}

/// The pure half of the calendar stage: what the fetch is turned into, what the
/// snapshot is allowed to carry, and the derivations of §4.
final class CalendarSnapshotTests: XCTestCase {

    private let day = Clock.at(0, 0)

    private func events(_ records: [CalendarEventRecord]) -> [EventOccurrence] {
        CalendarSnapshotBuilder.events(from: records, day: day, calendar: Clock.calendar)
    }

    // MARK: - Exclusion

    /// "All-day events are excluded and never enter the model — there is no
    /// meaningful instant to time a session against" (§2.3).
    func testAllDayEventsAreExcluded() {
        let allDay = CalendarEventRecord(
            eventIdentifier: "holiday",
            title: "Company holiday",
            startDate: Clock.at(0, 0),
            endDate: Clock.on(day: 5, 0, 0),
            isAllDay: true
        )
        let timed = CalendarEventRecord.timed("review", "Review", from: Clock.at(15, 30))

        XCTAssertEqual(events([allDay, timed]).map(\.title), ["Review"])
    }

    /// An occurrence with no identifier could be neither dismissed nor re-resolved, so
    /// it is not a suggestion anyone could act on.
    func testRecordsWithoutIdentityOrTimesAreDropped() {
        let unidentified = CalendarEventRecord(
            eventIdentifier: nil,
            title: "Nameless",
            startDate: Clock.at(15, 0),
            endDate: Clock.at(15, 30)
        )
        let empty = CalendarEventRecord(
            eventIdentifier: "",
            title: "Empty identifier",
            startDate: Clock.at(15, 0),
            endDate: Clock.at(15, 30)
        )
        let undated = CalendarEventRecord(
            eventIdentifier: "undated",
            title: "No start",
            startDate: nil,
            endDate: nil
        )

        XCTAssertTrue(events([unidentified, empty, undated]).isEmpty)
    }

    /// A multi-day event that began yesterday overlaps the fetch window, but its start
    /// is not a deadline today and its key belongs to another day's snapshot.
    func testOnlyOccurrencesStartingTodayAreKept() {
        let yesterday = CalendarEventRecord(
            eventIdentifier: "offsite",
            title: "Offsite",
            startDate: Clock.on(day: 3, 9, 0),
            endDate: Clock.at(17, 0)
        )
        let tomorrow = CalendarEventRecord.timed("standup", "Standup", from: Clock.on(day: 5, 9, 30))
        let today = CalendarEventRecord.timed("review", "Review", from: Clock.at(15, 30))

        XCTAssertEqual(events([yesterday, tomorrow, today]).map(\.title), ["Review"])
    }

    /// The same instance can surface twice when an event lives in two subscribed
    /// calendars.
    func testDuplicateOccurrencesCollapseByKey() {
        let record = CalendarEventRecord.timed("review", "Review", from: Clock.at(15, 30))

        XCTAssertEqual(events([record, record]).count, 1)
    }

    func testAnUntitledEventStillGetsARow() {
        let record = CalendarEventRecord(
            eventIdentifier: "blank",
            title: "   ",
            startDate: Clock.at(15, 0),
            endDate: Clock.at(15, 30)
        )

        XCTAssertEqual(events([record]).map(\.title), ["(No title)"])
    }

    // MARK: - Identity and order

    /// The recurring-identifier risk. `eventIdentifier` is shared by every occurrence,
    /// so identity is composite — and two occurrences of one recurring event on the
    /// same day must be two rows with two keys.
    func testRecurringOccurrencesGetDistinctCompositeKeys() {
        let first = CalendarEventRecord.timed("standup", "Standup", from: Clock.at(9, 30))
        let second = CalendarEventRecord.timed("standup", "Standup", from: Clock.at(16, 30))

        let built = events([first, second])

        XCTAssertEqual(built.count, 2)
        XCTAssertEqual(
            built[0].id,
            EventOccurrence.makeID(eventIdentifier: "standup", startsAt: Clock.at(9, 30))
        )
        XCTAssertEqual(
            built[1].id,
            EventOccurrence.makeID(eventIdentifier: "standup", startsAt: Clock.at(16, 30))
        )
        XCTAssertNotEqual(built[0].id, built[1].id, "one identifier, two occurrences")
    }

    func testOccurrencesAreSortedByStart() {
        let built = events([
            .timed("c", "Climbing", from: Clock.at(18, 30)),
            .timed("a", "Review", from: Clock.at(15, 30)),
            .timed("b", "One to one", from: Clock.at(16, 15)),
        ])

        XCTAssertEqual(built.map(\.title), ["Review", "One to one", "Climbing"])
    }

    /// §2.3: copying calendar data out from behind the TCC gate and into a plaintext
    /// plist argues for the least data that satisfies the stories, so the encoded
    /// record is asserted field by field — no notes, attendees, locations or URLs can
    /// arrive later without this failing.
    func testTheSnapshotCarriesNothingButTitleStartEndKeyAndColor() throws {
        let snapshot = CalendarSnapshotBuilder.snapshot(
            from: [.timed("review", "Review", from: Clock.at(15, 30))],
            access: .authorized,
            now: Clock.at(14, 13),
            calendar: Clock.calendar
        )

        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(snapshot)
        ) as? [String: Any]
        let event = try XCTUnwrap((json?["events"] as? [[String: Any]])?.first)

        XCTAssertEqual(
            Set(event.keys),
            ["id", "title", "startsAt", "endsAt", "colorHex"]
        )
        XCTAssertEqual(Set(try XCTUnwrap(json).keys), ["day", "events", "lastSyncedAt", "access"])
        XCTAssertEqual(snapshot.day, Clock.startOfDay(Clock.at(14, 13)))
        XCTAssertEqual(snapshot.lastSyncedAt, Clock.at(14, 13))
        XCTAssertEqual(snapshot.access, .authorized)
    }

    // MARK: - Re-resolution

    /// The snapshot is display and identity data, not authority (§2.3): a key the live
    /// store no longer agrees with resolves to nothing.
    func testAStaleKeyDoesNotResolve() {
        let key = EventOccurrence.makeID(eventIdentifier: "review", startsAt: Clock.at(15, 30))

        XCTAssertNil(
            CalendarSnapshotBuilder.resolve(key: key, in: [], day: day, calendar: Clock.calendar)
        )
    }

    /// The composite key is what makes a *moved* event fail rather than silently retime
    /// the session: the occurrence at the new time is a different occurrence.
    func testAnEventMovedToANewTimeNoLongerResolves() {
        let key = EventOccurrence.makeID(eventIdentifier: "review", startsAt: Clock.at(15, 30))
        let moved = [CalendarEventRecord.timed("review", "Review", from: Clock.at(16, 45))]

        XCTAssertNil(
            CalendarSnapshotBuilder.resolve(key: key, in: moved, day: day, calendar: Clock.calendar)
        )
    }

    func testAKeyTheStoreStillAgreesWithResolves() throws {
        let key = EventOccurrence.makeID(eventIdentifier: "review", startsAt: Clock.at(15, 30))
        let records = [
            CalendarEventRecord.timed("standup", "Standup", from: Clock.at(9, 30)),
            CalendarEventRecord.timed("review", "Review", from: Clock.at(15, 30)),
        ]

        let resolved = try XCTUnwrap(
            CalendarSnapshotBuilder.resolve(key: key, in: records, day: day, calendar: Clock.calendar)
        )

        XCTAssertEqual(resolved.title, "Review")
        XCTAssertEqual(resolved.startsAt, Clock.at(15, 30))
    }

    /// An all-day event cannot be resolved into a deadline even by key, because it is
    /// not in the model at all.
    func testAnAllDayKeyNeverResolves() {
        let record = CalendarEventRecord(
            eventIdentifier: "holiday",
            title: "Holiday",
            startDate: Clock.at(0, 0),
            endDate: Clock.on(day: 5, 0, 0),
            isAllDay: true
        )
        let key = EventOccurrence.makeID(eventIdentifier: "holiday", startsAt: Clock.at(0, 0))

        XCTAssertNil(
            CalendarSnapshotBuilder.resolve(
                key: key,
                in: [record],
                day: day,
                calendar: Clock.calendar
            )
        )
    }

    // MARK: - Access mapping

    func testTheThreeAccessStatesMapFromEventKit() {
        XCTAssertEqual(EventKitStore.access(for: .notDetermined), .notDetermined)
        XCTAssertEqual(EventKitStore.access(for: .fullAccess), .authorized)
        XCTAssertEqual(EventKitStore.access(for: .denied), .denied)
        XCTAssertEqual(EventKitStore.access(for: .restricted), .denied)
        // Write-only can list nothing, so it is no more useful to Cadence than denied.
        XCTAssertEqual(EventKitStore.access(for: .writeOnly), .denied)
    }
}

// MARK: - Derivations (§4)

final class CalendarDerivationsTests: XCTestCase {

    private let now = Clock.at(14, 13)

    private func snapshot(
        _ events: [EventOccurrence],
        access: CalendarAccess = .authorized
    ) -> CalendarSnapshot {
        CalendarSnapshot(
            day: Clock.startOfDay(now),
            events: events,
            lastSyncedAt: now,
            access: access
        )
    }

    private func occurrence(_ identifier: String, at startsAt: Date) -> EventOccurrence {
        EventOccurrence(
            id: EventOccurrence.makeID(eventIdentifier: identifier, startsAt: startsAt),
            title: identifier,
            startsAt: startsAt,
            endsAt: startsAt.addingTimeInterval(30 * minute)
        )
    }

    private func suggestion(
        _ snapshot: CalendarSnapshot?,
        dismissed: Set<String> = [],
        buffer: TimeInterval = 2 * minute
    ) -> EventOccurrence? {
        CalendarDerivations.suggestedEvent(
            in: snapshot,
            dismissed: dismissed,
            buffer: buffer,
            now: now,
            calendar: Clock.calendar
        )
    }

    func testTheSuggestionIsTheFirstEventFarEnoughAway() {
        let events = [occurrence("review", at: Clock.at(15, 30)), occurrence("oneToOne", at: Clock.at(16, 15))]

        XCTAssertEqual(suggestion(snapshot(events))?.title, "review")
    }

    /// "Dismiss … next one takes its place" — the suggestion is derived over the
    /// dismissal set, so removing one promotes the next with nothing promoting it.
    func testDismissingPromotesTheNextEvent() {
        let review = occurrence("review", at: Clock.at(15, 30))
        let oneToOne = occurrence("oneToOne", at: Clock.at(16, 15))
        let snapshot = snapshot([review, oneToOne])

        XCTAssertEqual(suggestion(snapshot, dismissed: [review.id])?.title, "oneToOne")
        XCTAssertNil(suggestion(snapshot, dismissed: [review.id, oneToOne.id]))
    }

    /// §4: `startsAt − buffer > now + 1 min`. The buffer is part of the test, not only
    /// of the deadline — an event inside it would yield a session already over.
    func testAnEventInsideTheBufferAndLeadIsNotSuggested() {
        let buffer = 2 * minute

        // 14:16:01 − 2 min = 14:14:01, which is one second past 14:13 + 1 min.
        XCTAssertNotNil(
            suggestion(snapshot([occurrence("soon", at: Clock.at(14, 16, 1))]), buffer: buffer)
        )
        // 14:16:00 − 2 min = 14:14:00, which is exactly the lead and so not *past* it.
        XCTAssertNil(
            suggestion(snapshot([occurrence("soon", at: Clock.at(14, 16))]), buffer: buffer)
        )
        XCTAssertNil(
            suggestion(snapshot([occurrence("past", at: Clock.at(13, 0))]), buffer: buffer)
        )
    }

    /// A bigger buffer can take an event out of the running altogether, which is the
    /// honest answer: there is no session left to run before it.
    func testTheBufferMovesTheThreshold() {
        let snapshot = snapshot([occurrence("soon", at: Clock.at(14, 17))])

        XCTAssertNotNil(suggestion(snapshot, buffer: 0))
        XCTAssertNil(suggestion(snapshot, buffer: 3 * minute))
    }

    func testThereIsNoSuggestionWithoutAnAuthorizedSnapshot() {
        let events = [occurrence("review", at: Clock.at(15, 30))]

        XCTAssertNil(suggestion(nil))
        XCTAssertNil(suggestion(snapshot(events, access: .denied)))
        XCTAssertNil(suggestion(snapshot(events, access: .notDetermined)))
    }

    // MARK: - canStartMeetingTimer

    func testAMeetingTimerCanOnlyStartFromIdleWithASuggestion() {
        let event = occurrence("review", at: Clock.at(15, 30))
        let running = SessionState.running(
            startedAt: Clock.at(14, 2),
            endsAt: Clock.at(14, 27),
            segmentStartedAt: Clock.at(14, 2)
        )

        XCTAssertTrue(
            CalendarDerivations.canStartMeetingTimer(for: .idle(), suggestion: event, now: now)
        )
        XCTAssertFalse(
            CalendarDerivations.canStartMeetingTimer(for: .idle(), suggestion: nil, now: now)
        )
        XCTAssertFalse(
            CalendarDerivations.canStartMeetingTimer(for: running, suggestion: event, now: now)
        )
    }

    /// D4: a session whose deadline elapsed while nothing was awake reads as complete,
    /// and the strip's action is the idle offer.
    func testAnElapsedSessionDoesNotOfferAMeetingTimer() {
        let elapsed = SessionState.running(
            startedAt: Clock.at(13, 30),
            endsAt: Clock.at(13, 55),
            segmentStartedAt: Clock.at(13, 30)
        )

        XCTAssertFalse(
            CalendarDerivations.canStartMeetingTimer(
                for: elapsed,
                suggestion: occurrence("review", at: Clock.at(15, 30)),
                now: now
            )
        )
    }

    // MARK: - meetingDuration

    /// P4 / §2.2: the deadline is `eventStart − buffer`, materialised at start.
    func testTheMeetingDurationSubtractsTheBuffer() {
        XCTAssertEqual(
            CalendarDerivations.meetingDuration(until: Clock.at(15, 30), buffer: 2 * minute, now: now),
            75 * minute
        )
        XCTAssertEqual(
            CalendarDerivations.meetingDuration(until: Clock.at(15, 30), buffer: 0, now: now),
            77 * minute
        )
    }

    func testThereIsNoDurationOnceTheBufferHasEatenIt() {
        XCTAssertNil(
            CalendarDerivations.meetingDuration(until: Clock.at(14, 14), buffer: 2 * minute, now: now)
        )
        XCTAssertNil(
            CalendarDerivations.meetingDuration(until: Clock.at(13, 0), buffer: 0, now: now)
        )
    }

    // MARK: - timeableDuration

    /// §4's one threshold, which is what every surface offering a meeting-linked start
    /// goes through. `meetingDuration` alone is only "positive", which is how the day
    /// list came to offer `Start 0m`.
    func testATimeableDurationHasToBeWorthOffering() {
        // 2 m 20 s away less a 2 m buffer is 20 seconds: a length, but not a session.
        XCTAssertNotNil(
            CalendarDerivations.meetingDuration(
                until: Clock.at(14, 15, 20), buffer: 2 * minute, now: now
            )
        )
        XCTAssertNil(
            CalendarDerivations.timeableDuration(
                until: Clock.at(14, 15, 20), buffer: 2 * minute, now: now
            )
        )
        // Exactly the minimum lead is not *past* it, matching `suggestedEvent`.
        XCTAssertNil(
            CalendarDerivations.timeableDuration(
                until: Clock.at(14, 16), buffer: 2 * minute, now: now
            )
        )
        XCTAssertEqual(
            CalendarDerivations.timeableDuration(
                until: Clock.at(14, 16, 1), buffer: 2 * minute, now: now
            ),
            CalendarDerivations.minimumLead + 1
        )
    }

    /// The threshold is one definition, not two that agree: what the strip's
    /// `suggestedEvent` accepts is exactly what `timeableDuration` gives a length for.
    func testTheSuggestionAndTheTimeableDurationAgreeAtTheThreshold() {
        for offsetSeconds in stride(from: 100, through: 200, by: 1) {
            let startsAt = now.addingTimeInterval(Double(offsetSeconds))
            let suggested = suggestion(snapshot([occurrence("event", at: startsAt)])) != nil
            let timeable = CalendarDerivations.timeableDuration(
                until: startsAt, buffer: 2 * minute, now: now
            ) != nil
            XCTAssertEqual(suggested, timeable, "disagreed \(offsetSeconds)s out")
        }
    }

    // MARK: - Freshness (§2.3, §4 `isSnapshotFresh`)

    /// The gate belongs wherever the snapshot is *read*, not only on the load from
    /// disk: nothing refreshes between 23:58 and 00:05 on an untouched machine.
    func testASnapshotForAnotherDaySuggestsNothing() {
        let events = [occurrence("review", at: Clock.at(15, 30))]
        let yesterdays = CalendarSnapshot(
            day: Clock.startOfDay(Clock.on(day: 3, 14, 13)),
            events: events,
            lastSyncedAt: Clock.on(day: 3, 23, 47),
            access: .authorized
        )

        XCTAssertNil(
            CalendarDerivations.suggestedEvent(
                in: yesterdays,
                dismissed: [],
                buffer: 2 * minute,
                now: now,
                calendar: Clock.calendar
            ),
            "false means the empty state, never yesterday's meetings"
        )
        // The same events under today's stamp are suggested, so it is the day that is
        // being refused rather than the events.
        XCTAssertNotNil(suggestion(snapshot(events)))
    }
}
