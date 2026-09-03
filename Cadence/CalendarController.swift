import AppKit
import EventKit
import Foundation

/// The app's live view of the calendar: access, today's snapshot, and today's
/// dismissals.
///
/// It is the calendar counterpart to `SessionController` and holds the same
/// discipline — the App Group container is canonical (P2), this is a cache that
/// writes through, and every value it hands a view is derived from the record plus a
/// clock the app layer owns. Only the app writes `calendarSnapshot` (§3), so there is
/// no cross-process race to observe here; what has to be watched is the *system*
/// store, which changes underneath the app and can have its permission revoked while
/// the app is running.
///
/// It does not touch `sessionState`. A refresh writes one key and a dismissal
/// another, which is why neither can retime a running session: there is no code path
/// from here to the session's deadline except `meetingStart(for:)`, which only ever
/// runs from a press.
@MainActor
@Observable
final class CalendarController {

    private(set) var access: CalendarAccess
    /// The snapshot as it was last fetched or read off disk. Not what a surface
    /// should render: read it through `snapshot(at:)`, which is where §4's freshness
    /// test lives.
    private(set) var storedSnapshot: CalendarSnapshot?
    private(set) var dismissed: Set<String>
    /// Whether the day list is drawn over the timer (`☰`). View state, not stored:
    /// it should not survive a relaunch.
    var isDayListExpanded = false
    /// The refresh in flight, if any. Exposed so a caller — and the suite — can await
    /// the fetch `init` kicks off rather than racing it.
    private(set) var refreshTask: Task<Void, Never>?

    private let store: SharedStore
    private let events: any CalendarEventReading
    private let calendar: Calendar
    private var observers: [any NSObjectProtocol] = []
    /// A low-frequency authorization poll. Revocation in System Settings raises no
    /// notification of any kind, and a menu-bar app can sit for hours between
    /// activations — long enough for the widget, a second process reading the same
    /// container, to render events from a calendar Cadence can no longer see.
    private var accessPoll: Task<Void, Never>?

    init(
        store: SharedStore = .shared,
        events: any CalendarEventReading = EventKitStore(),
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date(),
        observesSystem: Bool = true
    ) {
        self.store = store
        self.events = events
        self.calendar = calendar
        self.access = events.access
        self.storedSnapshot = store.loadCalendarSnapshot(now: now, calendar: calendar)
        self.dismissed = store.loadDismissedEvents(now: now, calendar: calendar).keys

        if observesSystem {
            observeSystem()
            pollAccess()
        }
        // A snapshot on disk is a starting point, not the truth: the day may have
        // rolled over, events may have moved, and access may have been revoked since
        // it was written. The fetch is off the main actor (§3 of this file's seam),
        // so launch starts it rather than waiting on it.
        startRefresh(now: now)
    }

    // MARK: - Derived

    /// Today's snapshot, or `nil` when the one in hand is not today's (§2.3, §4
    /// `isSnapshotFresh`).
    ///
    /// The gate is here, at the *read*, rather than only on the load from disk: the
    /// window can be open and frontmost across midnight with no calendar edit and no
    /// activation to trigger a refresh, and "false means show the empty state, never
    /// yesterday's meetings" has to hold in that minute too.
    func snapshot(at now: Date) -> CalendarSnapshot? {
        guard let storedSnapshot, storedSnapshot.isFresh(now, calendar: calendar) else {
            return nil
        }
        return storedSnapshot
    }

    /// The first event that is neither dismissed nor too close to time against (§4).
    func suggestion(buffer: TimeInterval, now: Date) -> EventOccurrence? {
        CalendarDerivations.suggestedEvent(
            in: snapshot(at: now),
            dismissed: dismissed,
            buffer: buffer,
            now: now,
            calendar: calendar
        )
    }

    // MARK: - Access

    /// The connect affordance. Prompts only from `notDetermined` — EventKit itself
    /// refuses to ask twice, so a denied user is sent to System Settings rather than
    /// shown a button that silently does nothing.
    ///
    /// `now` is a *clock*, not an instant, and it is read after the prompt returns:
    /// the permission sheet can sit unanswered for minutes, and a `now` captured at
    /// the press — which is what a `Date = Date()` default parameter is — would fetch
    /// and stamp a day that may no longer be the current one.
    func connect(now clock: @escaping () -> Date = Date.init) async {
        access = await events.requestAccess()
        await refresh(now: clock())
    }

    /// Opens the pane a denied user has to visit, since the prompt will not return.
    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Refresh

    /// Starts a refresh without waiting for it — the form every notification handler
    /// and `init` use, since none of them can await.
    ///
    /// Refreshes are serialized behind one another rather than overlapping: a mail
    /// account mid-sync fires `EKEventStoreChanged` repeatedly, and two fetches
    /// racing to assign `storedSnapshot` could land the older one last.
    func startRefresh(now: Date? = nil) {
        let previous = refreshTask
        refreshTask = Task { [weak self] in
            await previous?.value
            // `now` defaults to the instant the fetch actually runs, not to the one
            // the notification arrived on.
            await self?.refresh(now: now ?? Date())
        }
    }

    /// Re-reads access and, if it is granted, today's events; writes the snapshot.
    ///
    /// Revocation is handled here rather than anywhere special: access is read first,
    /// and anything short of authorized removes the stored snapshot (§2.3) so no
    /// surface — including a widget the app cannot see — can render stale events from
    /// behind a gate that has closed.
    ///
    /// The fetch is awaited off the main actor. Nothing is assigned across the
    /// suspension except at the end, back on the main actor, so a surface never sees
    /// a half-refreshed controller.
    func refresh(now: Date = Date()) async {
        access = events.access

        guard access == .authorized else {
            clearCalendarState()
            return
        }

        let day = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let fetched = await events.events(from: day, to: end)

        // Access can have been revoked during the fetch, in which case whatever came
        // back arrived from behind a gate that has since closed.
        access = events.access
        guard access == .authorized else {
            clearCalendarState()
            return
        }

        let next = CalendarSnapshotBuilder.snapshot(
            from: fetched,
            access: access,
            now: now,
            calendar: calendar
        )

        // The day may have rolled over since the dismissals were read, in which case
        // the store hands back an empty set for the new day (§2.4).
        dismissed = store.loadDismissedEvents(now: now, calendar: calendar).keys

        // Only a refresh that changed something earns a write. `lastSyncedAt` alone
        // differs on every single one, and writing the record reloads every widget
        // timeline and fires `didChange` on the suite — which costs the session
        // controller a re-read — on every activation and every store notification.
        if let current = storedSnapshot,
           current.day == next.day,
           current.access == next.access,
           current.events == next.events {
            return
        }

        guard store.save(next) else {
            NSLog("Cadence: calendar refresh dropped — the container refused the write")
            return
        }
        storedSnapshot = next
    }

    /// What a closed gate leaves behind: no snapshot on disk, none in memory, and no
    /// dismissals either — they are keys into a day's events the app can no longer
    /// see, and keeping them would hide rows in whatever day is fetched next.
    private func clearCalendarState() {
        storedSnapshot = nil
        dismissed = []
        store.removeCalendarSnapshot()
    }

    // MARK: - Dismissals

    /// `✕` on the strip, and the day list's rows. Dismissal is app state and is never
    /// written back to the `EKEvent` — the user's calendar is not ours to mutate
    /// (§2.4).
    ///
    /// The next event takes the dismissed one's place because the suggestion is
    /// *derived* over this set (§4), so nothing has to promote anything.
    func dismiss(_ key: String, now: Date = Date()) {
        guard !dismissed.contains(key) else { return }
        write(adding: [key], now: now)
    }

    /// `Undo hide` in the day list.
    func restore(_ key: String, now: Date = Date()) {
        guard dismissed.contains(key) else { return }
        write(removing: [key], now: now)
    }

    /// One dismissal, written against a set re-read from the container rather than
    /// against the one in memory.
    ///
    /// The in-memory set can belong to yesterday — the day rolls over and nothing
    /// refreshes until the next activation — and stamping *those* keys with today's
    /// date is exactly the drift §2.4's day-scoped container exists to make
    /// structurally impossible. The store discards another day's record on read, so
    /// re-reading is what makes the write self-correcting.
    private func write(
        adding added: Set<String> = [],
        removing removed: Set<String> = [],
        now: Date
    ) {
        let day = calendar.startOfDay(for: now)
        let current = store.loadDismissedEvents(now: now, calendar: calendar).keys
        let keys = current.union(added).subtracting(removed)

        guard store.save(DismissedEvents(day: day, keys: keys)) else {
            NSLog("Cadence: dismissal dropped — the container refused the write")
            return
        }
        dismissed = keys
    }

    // MARK: - Meeting-linked start (P4)

    /// Everything a meeting-linked start needs, resolved **at the moment Start is
    /// pressed** and never before (P4).
    ///
    /// The occurrence key is re-resolved against the live event store first: the
    /// snapshot is display and identity data, not authority (§2.3), and an event that
    /// has moved or been deleted since the last refresh must fail as "no suggestion"
    /// rather than start a timer against a time that no longer exists. The deadline
    /// is materialised here from the *live* start and the saved buffer, so the session
    /// keeps no pointer to the event and no later refresh or buffer change can retime
    /// it.
    func meetingStart(
        for key: String,
        buffer: TimeInterval,
        now: Date = Date()
    ) async -> MeetingStart? {
        guard access == .authorized else { return nil }

        let day = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let live = CalendarSnapshotBuilder.resolve(
            key: key,
            in: await events.events(from: day, to: end),
            day: now,
            calendar: calendar
        )
        guard let live else {
            NSLog("Cadence: meeting start declined — the occurrence no longer resolves")
            return nil
        }
        guard CalendarDerivations.meetingDuration(
            until: live.startsAt,
            buffer: buffer,
            now: now
        ) != nil else { return nil }

        return MeetingStart(
            key: live.id,
            title: live.title,
            endsAt: live.startsAt.addingTimeInterval(-max(0, buffer))
        )
    }

    // MARK: - System observation

    /// `EKEventStoreChanged` covers an edit made in Calendar.app; the day-change and
    /// clock-change notifications cover a rollover with nobody touching the machine;
    /// activation and wake cover everything that happened while the app was idle.
    ///
    /// Midnight is the one the day list needs: the window can be open and frontmost
    /// at 23:58 with no edits and no activation, and without a rollover signal the
    /// header would keep saying `TODAY` over yesterday's rows. The freshness gate in
    /// `snapshot(at:)` already makes that state safe; this is what makes it brief.
    private func observeSystem() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .EKEventStoreChanged,
            .NSCalendarDayChanged,
            .NSSystemClockDidChange,
            NSApplication.didBecomeActiveNotification,
        ]

        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.startRefresh() }
            }
        }

        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.startRefresh() }
            }
        )
    }

    /// Notices a revoked permission without waiting for an activation.
    ///
    /// `EKEventStore.authorizationStatus` is a type-level read, so a poll is cheap
    /// enough to sit beside the display ticker; it does no work at all unless the
    /// answer has changed. The interval is a compromise: revocation is rare, but the
    /// cost of noticing it late is the *widget* — a second process reading the same
    /// container — rendering events from behind a gate that has closed, so seconds
    /// rather than minutes.
    ///
    /// It holds `self` weakly and ends the first time it wakes to find it gone, which
    /// is why there is no `deinit` to tear down: a `deinit` is nonisolated and could
    /// not reach main-actor state to do it anyway.
    private func pollAccess() {
        accessPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                guard self.events.access != self.access else { continue }
                self.startRefresh()
            }
        }
    }
}

/// A meeting-linked start, fully materialised (P4): the title copied, the deadline
/// computed from the live event start less the saved buffer, and the occurrence key
/// recorded as provenance.
///
/// It carries a *deadline* rather than a duration so that both surfaces produce the
/// same `endsAt` down to the millisecond — the transition subtracts its own `now`,
/// which is the instant the write actually happens.
struct MeetingStart: Equatable, Sendable {
    var key: String
    var title: String
    /// `eventStart − buffer`.
    var endsAt: Date
}
