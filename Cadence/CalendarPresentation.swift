import SwiftUI

/// What the calendar surfaces show, decided as pure functions of the snapshot, the
/// dismissal set, the buffer and `now`.
///
/// The strip has four states and the day list three kinds of row, and none of that
/// belongs in a view body: "dismissing promotes the next event" and "revocation
/// degrades to the empty state" are testable facts here and only claims in a
/// `ViewBuilder`.
enum StripContent: Equatable {
    /// `notDetermined` — the connect affordance, which is the only thing that
    /// prompts. Cadence never asks at launch: the permission sheet is a response to
    /// the user reaching for the calendar, not to them opening a timer.
    case connect
    /// `denied`, or revoked while running. No stale events (§2.3).
    case denied
    /// Authorized, and nothing left to suggest — either the day is empty or every
    /// remaining event has been dismissed, which is why the copy says "nothing
    /// *else*" (§3.3).
    case empty
    /// The next event worth timing against.
    case event(EventRow)

    var row: EventRow? {
        if case .event(let row) = self { return row }
        return nil
    }
}

/// The strip's event row, and the day list's rows, in the form the views draw.
struct EventRow: Equatable, Identifiable {
    var id: String
    var title: String
    /// `3:30 PM`.
    var timeText: String
    /// `3:30 PM · in 77 min · ends 2 min early` — the buffer clause only when the
    /// buffer is on, because "ends 0 min early" is not a thing to promise.
    var metaText: String
    /// `Timer until 3:30`, the strip's action, absent when there is nothing to
    /// start — a session already running, or an event the buffer has eaten.
    var actionText: String?
    /// `Start 120m`, the day list's action for the same event.
    var listActionText: String?
    var colorHex: String?
    var isDismissed: Bool

    /// The source calendar's color (§1.2), falling back to the event accent for a
    /// calendar that reported none. Dismissed rows drop the bar to 40%.
    var barColor: Color {
        let base = EventRow.barColor(for: colorHex)
        return isDismissed ? base.opacity(DesignTokens.dismissedBarOpacity) : base
    }

    static func barColor(for event: EventOccurrence) -> Color {
        barColor(for: event.colorHex)
    }

    static func barColor(for colorHex: String?) -> Color {
        colorHex.flatMap(Color.init(hexString:)) ?? DesignTokens.Accent.event
    }

    var titleColor: Color {
        isDismissed ? DesignTokens.TextColor.dismissed : DesignTokens.TextColor.primary
    }
}

/// The expanded day list (`☰`): every timed event today, dismissed ones included and
/// struck through, over the timer.
struct DayListContent: Equatable {
    /// `TODAY · WEDNESDAY`.
    var headerText: String
    /// `synced 2:13 PM`, or nil before the first sync.
    var syncedText: String?
    var rows: [EventRow]
    /// `4 events today · 1 hidden`.
    var footerText: String
}

/// What the dropdown puts in its one calendar slot (§3.3).
///
/// Four cases rather than "a meeting or the empty copy", because the copy is only
/// true in one of the other three — see `CalendarPresentation.dropdownCalendar`.
enum DropdownCalendarContent: Equatable {
    /// `notDetermined`: the row that prompts, and the only connect affordance a
    /// user who never opens the window will ever see.
    case connect
    /// `denied` or revoked. The prompt will not return, so the row goes to System
    /// Settings instead of pretending it can ask.
    case denied
    /// Authorized, with something worth timing against.
    case meeting(DurationPreset)
    /// Authorized, and the day is genuinely empty — or done, or entirely dismissed.
    case empty

    /// The row's label, for every case that is copy rather than a preset.
    var copy: String? {
        switch self {
        case .connect: "Connect your calendar"
        case .denied: "Calendar access is off"
        case .meeting: nil
        // §3.3 verbatim, and only where it is a true statement about a day.
        case .empty: "Nothing on your calendar today"
        }
    }

    var preset: DurationPreset? {
        if case .meeting(let preset) = self { return preset }
        return nil
    }
}

enum CalendarPresentation {
    private static let times = FormatterCache(template: "jmm")
    private static let weekdays = FormatterCache(template: "EEEE")

    // MARK: - Strip

    static func strip(
        snapshot: CalendarSnapshot?,
        access: CalendarAccess,
        dismissed: Set<String>,
        state: SessionState,
        buffer: TimeInterval,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> StripContent {
        switch access {
        case .notDetermined: return .connect
        case .denied: return .denied
        case .authorized: break
        }

        guard let suggestion = CalendarDerivations.suggestedEvent(
            in: snapshot,
            dismissed: dismissed,
            buffer: buffer,
            now: now,
            calendar: calendar
        ) else { return .empty }

        return .event(
            row(
                for: suggestion,
                dismissed: dismissed,
                canStart: CalendarDerivations.canStartMeetingTimer(
                    for: state,
                    suggestion: suggestion,
                    now: now
                ),
                buffer: buffer,
                now: now,
                locale: locale,
                timeZone: timeZone
            )
        )
    }

    // MARK: - Day list

    static func dayList(
        snapshot: CalendarSnapshot?,
        dismissed: Set<String>,
        state: SessionState,
        buffer: TimeInterval,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> DayListContent {
        // A snapshot for another day is not this day's list. The header says `TODAY`,
        // so a stale one would put that word over yesterday's meetings and a
        // `synced 11:47 PM` under it — §2.3 asks for the empty state instead.
        let fresh = snapshot.flatMap { $0.isFresh(now, calendar: calendar) ? $0 : nil }
        let events = fresh?.events ?? []
        // Only today's dismissals of today's events count towards "1 hidden": a key
        // for an event that has since been deleted is not a row anyone can unhide.
        let hidden = events.count { dismissed.contains($0.id) }

        return DayListContent(
            headerText: headerText(now, locale: locale, timeZone: timeZone),
            syncedText: fresh.map {
                "synced \(times.formatter(locale: locale, timeZone: timeZone).string(from: $0.lastSyncedAt))"
            },
            rows: events.map {
                row(
                    for: $0,
                    dismissed: dismissed,
                    // A row is startable on the same terms the strip's action is:
                    // idle, and far enough away to be a session (§4).
                    canStart: state.effectiveStatus(now) == .idle,
                    buffer: buffer,
                    now: now,
                    locale: locale,
                    timeZone: timeZone
                )
            },
            footerText: footerText(events: events.count, hidden: hidden)
        )
    }

    /// `4 events today · 1 hidden`, with the hidden clause omitted when nothing is.
    static func footerText(events: Int, hidden: Int) -> String {
        let counted = "\(events) event\(events == 1 ? "" : "s") today"
        return hidden > 0 ? "\(counted) · \(hidden) hidden" : counted
    }

    // MARK: - Dropdown

    /// The dropdown's `To Design review` row (§7's "Pick from calendar events").
    ///
    /// Unlike the two `clockTargets` beside it this row *does* carry the buffer
    /// (D7): a clock target means what its label says, whereas a meeting row's whole
    /// purpose is not to still be running when the meeting starts.
    static func meetingPreset(
        for suggestion: EventOccurrence?,
        buffer: TimeInterval,
        now: Date
    ) -> DurationPreset? {
        guard let suggestion,
              let duration = CalendarDerivations.meetingDuration(
                  until: suggestion.startsAt,
                  buffer: buffer,
                  now: now
              )
        else { return nil }

        return DurationPreset(
            id: "event-\(suggestion.id)",
            title: "To \(suggestion.title)",
            duration: duration
        )
    }

    /// The dropdown's one calendar row, which is a row about *access* before it is a
    /// row about the day.
    ///
    /// §3.3 gives the dropdown `Nothing on your calendar today` — a fact about the
    /// day — so it may only be said when there *is* a day to state a fact about.
    /// Behind an unopened gate it is simply false, and it was being said while the
    /// window's strip was correctly offering `Connect` two hundred points away.
    ///
    /// The connect row also has to exist here at all: Stage 3 owes a connect
    /// affordance, and a user who never opens the window has no other way to reach
    /// one.
    static func dropdownCalendar(
        access: CalendarAccess,
        suggestion: EventOccurrence?,
        buffer: TimeInterval,
        now: Date
    ) -> DropdownCalendarContent {
        switch access {
        case .notDetermined:
            return .connect
        case .denied:
            return .denied
        case .authorized:
            guard let suggestion,
                  let preset = meetingPreset(for: suggestion, buffer: buffer, now: now)
            else { return .empty }
            return .meeting(preset)
        }
    }

    // MARK: - Rows

    private static func row(
        for event: EventOccurrence,
        dismissed: Set<String>,
        canStart: Bool,
        buffer: TimeInterval,
        now: Date,
        locale: Locale,
        timeZone: TimeZone
    ) -> EventRow {
        let time = times.formatter(locale: locale, timeZone: timeZone).string(from: event.startsAt)
        let isDismissed = dismissed.contains(event.id)
        // §4's one threshold, which is the strip's and the list's alike: an event
        // whose remaining lead is under a minute is not a session either surface
        // offers. `meetingDuration` alone would let the list offer `Start 0m` and
        // then start a twenty-second timer.
        let duration = CalendarDerivations.timeableDuration(
            until: event.startsAt,
            buffer: buffer,
            now: now
        )
        let startable = canStart && !isDismissed && duration != nil

        return EventRow(
            id: event.id,
            title: event.title,
            timeText: time,
            metaText: metaText(time: time, startsAt: event.startsAt, buffer: buffer, now: now),
            // The label promises the event's own start, not the buffered deadline:
            // "Timer until 3:30" is where the user has to be, and the meta line
            // beside it is what says the timer stops two minutes short.
            actionText: startable ? "Timer until \(clockOnly(time, locale: locale, timeZone: timeZone, date: event.startsAt))" : nil,
            listActionText: startable ? "Start \(minutes(duration ?? 0))m" : nil,
            colorHex: event.colorHex,
            isDismissed: isDismissed
        )
    }

    /// `3:30 PM · in 77 min · ends 2 min early`.
    private static func metaText(
        time: String,
        startsAt: Date,
        buffer: TimeInterval,
        now: Date
    ) -> String {
        var parts = [time]
        let lead = startsAt.timeIntervalSince(now)
        if lead > 0 { parts.append("in \(minutes(lead)) min") }
        if buffer > 0 { parts.append("ends \(minutes(buffer)) min early") }
        return parts.joined(separator: " · ")
    }

    /// `TODAY · WEDNESDAY`, uppercased here because the token is a font, not a
    /// transform.
    private static func headerText(_ now: Date, locale: Locale, timeZone: TimeZone) -> String {
        let weekday = weekdays.formatter(locale: locale, timeZone: timeZone).string(from: now)
        return "TODAY · \(weekday.uppercased(with: locale))"
    }

    /// The action label drops the day period — `Timer until 3:30` — because the
    /// event's own time sits two lines away and the period would only pad the button.
    private static func clockOnly(
        _ time: String,
        locale: Locale,
        timeZone: TimeZone,
        date: Date
    ) -> String {
        let period = periods.formatter(locale: locale, timeZone: timeZone).string(from: date)
        guard !period.isEmpty else { return time }
        return time
            .replacingOccurrences(of: period, with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static let periods = FormatterCache(template: "a")

    private static func minutes(_ interval: TimeInterval) -> Int {
        Int((interval / 60).rounded())
    }
}
