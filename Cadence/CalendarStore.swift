import EventKit
import Foundation

/// The seam over EventKit.
///
/// Everything Cadence needs from the system store is three things: what access it
/// has, a way to ask for it, and the expanded occurrences in a window. Naming that
/// as a protocol is what makes recurrence expansion, all-day exclusion and the three
/// access states testable against fixtures instead of against whoever's calendar the
/// test happens to run on (testing strategy §6). `EventKitStore` is the one
/// implementation that talks to `EKEventStore`; `FixtureEventStore` in the suite is
/// the other.
///
/// The protocol is deliberately dumb: it converts `EKEvent` to a value type and
/// stops. Exclusion, keying, sorting and freshness are pure functions over those
/// values (`CalendarSnapshotBuilder`), so the interesting logic is on the testable
/// side of the seam rather than behind it.
protocol CalendarEventReading: Sendable {
    /// The current authorization, read fresh — it can be revoked from System
    /// Settings while the app is running, which terminates nothing.
    var access: CalendarAccess { get }

    /// Prompts if and only if access is `notDetermined`; returns the resulting
    /// state either way.
    func requestAccess() async -> CalendarAccess

    /// Occurrences overlapping `start..<end`, one per instance of a recurring
    /// event. All-day events are included here and excluded by the builder, so the
    /// exclusion is a tested rule rather than a hidden property of the fetch.
    ///
    /// `async` because the one real implementation of it is not: enumerating an
    /// `EKEventStore` is the documented-expensive call, and Apple's guidance is to
    /// keep it off the main thread. The seam carries the hop so the *caller* — a
    /// `@MainActor` controller refreshed from launch and from three notifications —
    /// never blocks the run loop on a CalDAV account mid-sync.
    func events(from start: Date, to end: Date) async -> [CalendarEventRecord]
}

/// One `EKEvent` as the seam surfaces it: the fields the snapshot needs plus the two
/// the builder decides with (`isAllDay`, `eventIdentifier`).
///
/// Notes, attendees, locations and URLs are not here and never reach the container
/// (§2.3) — the type cannot carry them.
struct CalendarEventRecord: Equatable, Sendable {
    /// Shared by every occurrence of a recurring event, hence the composite key.
    /// Optional because `EKEvent.eventIdentifier` is, and an occurrence without one
    /// has no identity to dismiss or re-resolve against.
    var eventIdentifier: String?
    var title: String?
    var startDate: Date?
    var endDate: Date?
    var isAllDay: Bool
    /// The source calendar's color as `RRGGBB`.
    var colorHex: String?

    init(
        eventIdentifier: String?,
        title: String?,
        startDate: Date?,
        endDate: Date?,
        isAllDay: Bool = false,
        colorHex: String? = nil
    ) {
        self.eventIdentifier = eventIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.colorHex = colorHex
    }
}

// MARK: - Snapshot building

/// Turns fetched records into the record the container holds. Pure, so every rule
/// below is a test rather than a claim.
enum CalendarSnapshotBuilder {

    /// Today's timed occurrences, sorted, keyed, and stripped to §2.3's fields.
    ///
    /// The rules, in order:
    /// - **All-day events are excluded** and never enter the model — there is no
    ///   meaningful instant to time a session against (§2.3).
    /// - An occurrence with no `eventIdentifier`, no start or no end is dropped: it
    ///   has no identity, so it could be neither dismissed nor re-resolved, and a
    ///   suggestion that cannot be dismissed is worse than no suggestion.
    /// - Only occurrences **starting** within the day are kept. A multi-day event
    ///   that began yesterday overlaps the fetch window but its start is not a
    ///   deadline today, and its key would belong to another day's snapshot.
    /// - The key is `eventIdentifier|occurrenceStartEpoch`. EventKit expands
    ///   recurrences into one record per occurrence, each with its own start, so the
    ///   composite is unique per instance even though the identifier is not.
    /// - Duplicates by key are collapsed, keeping the first: the same instance can
    ///   surface twice when an event is present in two subscribed calendars.
    static func events(
        from records: [CalendarEventRecord],
        day: Date,
        calendar: Calendar = .current
    ) -> [EventOccurrence] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        var seen = Set<String>()
        return records
            .compactMap { record -> EventOccurrence? in
                guard !record.isAllDay,
                      let identifier = record.eventIdentifier, !identifier.isEmpty,
                      let startsAt = record.startDate,
                      let endsAt = record.endDate,
                      startsAt >= dayStart, startsAt < dayEnd
                else { return nil }

                return EventOccurrence(
                    id: EventOccurrence.makeID(eventIdentifier: identifier, startsAt: startsAt),
                    // A calendar event with no title is legal; "(No title)" is
                    // presentation for a row that still has a time worth timing to.
                    title: record.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        ?? "(No title)",
                    startsAt: startsAt,
                    endsAt: endsAt,
                    colorHex: record.colorHex
                )
            }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.startsAt < $1.startsAt }
    }

    /// The whole record, for the day containing `now`.
    static func snapshot(
        from records: [CalendarEventRecord],
        access: CalendarAccess,
        now: Date,
        calendar: Calendar = .current
    ) -> CalendarSnapshot {
        CalendarSnapshot(
            day: calendar.startOfDay(for: now),
            events: events(from: records, day: now, calendar: calendar),
            lastSyncedAt: now,
            access: access
        )
    }

    /// Re-resolves an occurrence key against freshly fetched records, returning the
    /// occurrence the live store agrees exists **now**.
    ///
    /// This is the answer to the recurring-identifier risk. The snapshot is display
    /// and identity data, not authority (§2.3): a key whose event was moved, deleted
    /// or re-synced under a new identifier simply does not match, and the caller
    /// gets `nil` — a stale key fails as "no suggestion", never as a wrong timer.
    /// Matching is on the composite key, so an event rescheduled to a different time
    /// is a *different* occurrence and correctly fails to resolve rather than
    /// silently retiming the session to its new start.
    static func resolve(
        key: String,
        in records: [CalendarEventRecord],
        day: Date,
        calendar: Calendar = .current
    ) -> EventOccurrence? {
        events(from: records, day: day, calendar: calendar).first { $0.id == key }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - The live store

/// The one place Cadence talks to EventKit.
///
/// Cadence only ever reads, but EventKit has no read-only access level — `writeOnly`
/// is exactly that, write-only — so full access is the least that satisfies the
/// stories, requested with `NSCalendarsFullAccessUsageDescription`. Nothing here
/// writes: there is no `save`, no `remove`, and dismissal is app state that never
/// goes back to an `EKEvent` (§2.4).
///
/// An `actor` rather than a class with an unchecked conformance: `EKEventStore` is
/// not `Sendable`, and the honest way to share it across a `@MainActor` controller
/// and a background fetch is isolation the compiler enforces, not an escape hatch
/// asserting there is nothing to enforce. Being an actor is also what moves
/// `events(from:to:)` off the main thread — the call hops to the actor's executor,
/// which is the cooperative pool.
actor EventKitStore: CalendarEventReading {
    /// One store for the app's lifetime. `EKEventStore` is documented as expensive
    /// to create and posts `EKEventStoreChanged` for changes made anywhere, which is
    /// the signal the controller refreshes on.
    private let store = EKEventStore()

    /// `nonisolated` because it touches no actor state: the authorization status is
    /// a type-level read, which is what lets the controller check access — and
    /// notice a revocation — without an await.
    nonisolated var access: CalendarAccess {
        Self.access(for: EKEventStore.authorizationStatus(for: .event))
    }

    /// `writeOnly` and `restricted` both read as `denied`: neither can list an
    /// event, so neither is a state the strip can show anything in.
    static func access(for status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .fullAccess: .authorized
        default: .denied
        }
    }

    func requestAccess() async -> CalendarAccess {
        guard access == .notDetermined else { return access }
        _ = try? await store.requestFullAccessToEvents()
        return access
    }

    /// Actor-isolated, so every caller reaches it with an await and the enumeration
    /// runs on the cooperative pool rather than on whichever run loop asked.
    func events(from start: Date, to end: Date) -> [CalendarEventRecord] {
        guard access == .authorized else { return [] }
        // `calendars: nil` is every calendar the user has, which is what "today's
        // events" means; the expansion of recurring events into one `EKEvent` per
        // occurrence is this predicate's doing, and what makes the composite key
        // well-defined (§2.3).
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(Self.record)
    }

    private static func record(_ event: EKEvent) -> CalendarEventRecord {
        CalendarEventRecord(
            eventIdentifier: event.eventIdentifier,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            colorHex: event.calendar?.cgColor.flatMap(Self.hex)
        )
    }

    /// `RRGGBB` in sRGB. A calendar color in another space is converted rather than
    /// dropped, and a color that cannot be converted falls back to the event accent
    /// at the view.
    private static func hex(_ color: CGColor) -> String? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3
        else { return nil }

        let channel = { (value: CGFloat) in Int((min(1, max(0, value)) * 255).rounded()) }
        return String(
            format: "%02X%02X%02X",
            channel(components[0]),
            channel(components[1]),
            channel(components[2])
        )
    }
}
