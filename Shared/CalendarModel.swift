import Foundation

/// One expanded occurrence of a calendar event.
///
/// `EKEvent.eventIdentifier` is shared by every occurrence of a recurring event
/// and is not guaranteed stable across edits, so identity is composite: the event
/// identifier joined to the occurrence's start epoch. Callers treat `id` as an
/// opaque string; only `makeID` knows its shape.
struct EventOccurrence: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var startsAt: Date
    var endsAt: Date
    /// The source calendar's own color as `RRGGBB`, because the visual
    /// specification (§1.2) has calendar rows inherit it rather than share one
    /// accent. A string rather than a `CGColor` because the snapshot is JSON in a
    /// plist and a color reference is neither `Codable` nor `Sendable`; `nil` falls
    /// back to the event accent.
    ///
    /// This is the whole extent of the addition to §2.3's minimal record — a six
    /// character presentation value, carrying nothing about the event itself.
    var colorHex: String?

    init(
        id: String,
        title: String,
        startsAt: Date,
        endsAt: Date,
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.colorHex = colorHex
    }

    static func makeID(eventIdentifier: String, startsAt: Date) -> String {
        "\(eventIdentifier)|\(Int(startsAt.timeIntervalSince1970))"
    }
}

enum CalendarAccess: String, Codable, Sendable {
    case notDetermined, denied, authorized
}

/// The app's copy of today's timed events, written so the widget has something to
/// render without querying EventKit itself.
///
/// Display and identity data, never authority: an occurrence key is re-resolved
/// against the live event store before a meeting-linked deadline is computed. Kept
/// deliberately minimal — copying event data out from behind the TCC gate and into
/// a container plist argues for the least data that satisfies the stories.
struct CalendarSnapshot: Codable, Equatable, Sendable {
    /// Start of the day this snapshot covers. A snapshot for another day is
    /// discarded on read rather than shown.
    var day: Date
    /// Sorted by `startsAt`; all-day events are excluded, having no instant to
    /// time a session against.
    var events: [EventOccurrence]
    var lastSyncedAt: Date
    var access: CalendarAccess = .notDetermined
}

/// Occurrences the user has dismissed from the suggestion strip.
///
/// The whole record is day-scoped rather than pruned key by key: expiry is one
/// date comparison, growth is bounded by a single day's events, and the invariant
/// stays structural instead of depending on the key's string encoding. Kept apart
/// from `CalendarSnapshot` so a calendar refresh cannot clobber dismissals.
struct DismissedEvents: Codable, Equatable, Sendable {
    var day: Date
    var keys: Set<String>

    init(day: Date, keys: Set<String> = []) {
        self.day = day
        self.keys = keys
    }
}
