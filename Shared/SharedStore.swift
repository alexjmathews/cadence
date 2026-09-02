import Foundation
import WidgetKit

/// The four records in the App Group container, which is the one source of truth
/// (P2). Every value is JSON-encoded `Data` under its own key, so each record can
/// be validated on read without reference to the others.
///
/// Writes report whether the container took them. The suite can fail to resolve —
/// a missing entitlement, a malformed group identifier — and a caller that assumed
/// success would keep a live in-memory state disagreeing with disk, which is the
/// one failure four surfaces cannot recover from on their own.
///
/// The day-scoped reads take their `Calendar` per call rather than storing one.
/// `Calendar.current` is a snapshot: captured once in a long-lived menu-bar app it
/// would still be in yesterday's time zone after a DST flip or a flight, while a
/// freshly spawned widget process used the new one — and the two would then
/// disagree about which day a snapshot or a dismissal belongs to.
///
/// `UserDefaults` is documented thread-safe, hence the unchecked conformance.
struct SharedStore: @unchecked Sendable {
    static let appGroupID = "group.com.alexmathews.cadence"
    static let shared = SharedStore()

    enum Key {
        static let sessionState = "sessionState"
        static let preferences = "preferences"
        static let dismissedEvents = "dismissedEvents"
        static let calendarSnapshot = "calendarSnapshot"
    }

    private let defaults: UserDefaults?
    private let reloadsWidgets: Bool

    init(suiteName: String = SharedStore.appGroupID, reloadsWidgets: Bool = true) {
        self.defaults = UserDefaults(suiteName: suiteName)
        self.reloadsWidgets = reloadsWidgets
    }

    // MARK: - Session state

    /// The current session, reconciled against `now` so a deadline that elapsed
    /// while the app was quit is already folded in.
    func loadSessionState(now: Date) -> SessionState {
        let stored = decode(SessionState.self, forKey: Key.sessionState) ?? SessionState()
        return SessionTransitions.reconciled(stored, now: now)
    }

    @discardableResult
    func save(_ state: SessionState) -> Bool {
        write(state, forKey: Key.sessionState)
    }

    // MARK: - Preferences

    /// Unconditional: preferences carry no scope and are required to survive
    /// relaunch, so a missing record means defaults, never an error.
    func loadPreferences() -> Preferences {
        decode(Preferences.self, forKey: Key.preferences) ?? Preferences()
    }

    @discardableResult
    func save(_ preferences: Preferences) -> Bool {
        write(preferences, forKey: Key.preferences)
    }

    // MARK: - Dismissals

    /// Today's dismissals. A record for another day is discarded wholesale rather
    /// than pruned, and replaced by the next write.
    func loadDismissedEvents(now: Date, calendar: Calendar = .autoupdatingCurrent) -> DismissedEvents {
        let today = calendar.startOfDay(for: now)
        guard let stored = decode(DismissedEvents.self, forKey: Key.dismissedEvents),
              stored.day == today
        else {
            return DismissedEvents(day: today)
        }
        return stored
    }

    @discardableResult
    func save(_ dismissed: DismissedEvents) -> Bool {
        write(dismissed, forKey: Key.dismissedEvents)
    }

    // MARK: - Calendar snapshot

    /// Today's snapshot, or `nil` when there is none or it is stale. Callers show
    /// the empty state on `nil`; yesterday's meetings are never shown.
    func loadCalendarSnapshot(now: Date, calendar: Calendar = .autoupdatingCurrent) -> CalendarSnapshot? {
        guard let stored = decode(CalendarSnapshot.self, forKey: Key.calendarSnapshot),
              stored.isFresh(now, calendar: calendar)
        else {
            return nil
        }
        return stored
    }

    @discardableResult
    func save(_ snapshot: CalendarSnapshot) -> Bool {
        write(snapshot, forKey: Key.calendarSnapshot)
    }

    /// Calendar access can be revoked, and stale events must not outlive it.
    @discardableResult
    func removeCalendarSnapshot() -> Bool {
        guard let defaults else { return false }
        defaults.removeObject(forKey: Key.calendarSnapshot)
        return true
    }

    // MARK: - Container access

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Reports that the suite resolved and the record encoded — the two failures a
    /// caller can act on.
    ///
    /// It deliberately does not claim the bytes reached disk. `set` populates the
    /// in-process cache and every read available to us reads that same cache, so a
    /// read-back would return the value just written even when `cfprefsd` refuses
    /// the record; it would report success precisely in the case worth catching.
    /// Confirming persistence needs the container itself, which is what the App
    /// Group round-trip suite checks.
    private func write<T: Encodable>(_ value: T, forKey key: String) -> Bool {
        guard let defaults else {
            NSLog("Cadence: App Group suite unavailable; dropped write for \(key)")
            return false
        }
        guard let data = try? JSONEncoder().encode(value) else {
            NSLog("Cadence: failed to encode \(key)")
            return false
        }
        defaults.set(data, forKey: key)
        if reloadsWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
        return true
    }
}
