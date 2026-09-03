import Foundation

/// What the widget draws, decided as pure functions of the session, the calendar
/// snapshot, the preferences and `now`.
///
/// None of it lives in a view body. "Suggestions are absent while running" and "the
/// pane falls back to `displayName` when the session has no title" are exit criteria,
/// and an exit criterion asserted by a `ViewBuilder` is an exit criterion nobody can
/// test. The views below this take a `WidgetTile` and a `WidgetPane` and draw them.

// MARK: - Countdown

/// The numerals. A running session hands SwiftUI a range and lets it count (P1, and
/// the visual specification's implementation note): the widget is not the menu bar,
/// so D1's ticker does not apply and no process has to be awake for the digits to be
/// right. Every other state is a fixed string.
enum WidgetCountdown: Equatable, Sendable {
    /// `Text(timerInterval:countsDown: true)`.
    case interval(ClosedRange<Date>)
    /// `25:00`, `00:00`, or a paused session's frozen remainder.
    case text(String)
}

// MARK: - Controls

/// One widget control: a label and the single App Intent behind it (§4). There is no
/// case for a control that does two things, because there is no such control.
struct WidgetControl: Equatable, Sendable {
    var title: String
    var action: WidgetAction
    /// `↺` is drawn from the symbol set rather than typed, so `title` is the
    /// accessibility label and the symbol name is the view's business.
    var isGlyph: Bool = false

    /// The reset control, which is the same glyph in every state that offers it.
    static let resetGlyph = WidgetControl(title: "Reset", action: .reset, isGlyph: true)
}

// MARK: - Tile

/// The leading column of both families: status line, numerals, progress rule,
/// caption, transport. Identical in the small card and the medium one.
struct WidgetTile: Equatable, Sendable {
    /// Derived, never the stored value (D4). The views colour the shell from it.
    var status: SessionStatus
    /// `next 3:30 PM` · `ends 2:27 PM` · `ended 2:13 PM`. Absent when there is
    /// nothing to say — an idle day with no suggestion left has no clock to name.
    var statusText: String?
    var countdown: WidgetCountdown
    var progress: Double
    /// `Ready` · the session's `displayName` · `Complete · 25 min`.
    var caption: String
    var primary: WidgetControl
    /// Absent while idle, where `Start` is the only thing on offer.
    var secondary: WidgetControl?
}

// MARK: - Pane

/// A row in the medium's idle pane. Either a control — a duration, a clock target, a
/// meeting — or the empty-calendar copy, which is a row so that the pane keeps its
/// shape rather than collapsing to nothing.
struct WidgetSuggestion: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    /// `45m`, at the row's trailing edge. Copy rows have none.
    var metaText: String?
    /// The source calendar's colour for a meeting row; `nil` leaves the reserved
    /// slot in its neutral mark, which is what keeps every title on one column.
    var barColorHex: String?
    /// `nil` means the row is copy, not a control.
    var action: WidgetAction?
}

/// The medium's trailing column.
enum WidgetPane: Equatable, Sendable {
    /// Idle: what else could be started.
    case suggestions([WidgetSuggestion])
    /// Running, paused or complete: what *is* being worked on. The suggestions are
    /// deliberately gone — the medium's story while a session runs is showing the
    /// user their session, not tempting them with three others.
    case session(label: String, title: String, meta: String?)
}

// MARK: - Presentation

enum WidgetPresentation {
    private static let times = FormatterCache(template: "jmm")

    /// The empty-calendar row, in place of a blank one. The widget states a fact
    /// about the day, as the dropdown does (§3.3) — it offers no dismissal and so
    /// never reaches the "nothing *else*" case the window strip has.
    static let emptyCalendarCopy = "Nothing on your calendar today"

    // MARK: Tile

    static func tile(
        for state: SessionState,
        suggestion: EventOccurrence? = nil,
        now: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> WidgetTile {
        let status = state.effectiveStatus(now)
        let clock = times.formatter(locale: locale, timeZone: timeZone)

        switch status {
        case .idle:
            return WidgetTile(
                status: status,
                // The idle line names what is coming, which is the only forward-
                // looking thing an idle widget knows. With nothing suggested it says
                // nothing rather than inventing a clock.
                statusText: suggestion.map { "next \(clock.string(from: $0.startsAt))" },
                countdown: .text(ClockFormatter.text(state.remaining(now))),
                progress: 0,
                caption: "Ready",
                primary: WidgetControl(
                    title: "Start \(minutes(state.plannedDuration)) min",
                    action: .start
                ),
                secondary: nil
            )

        case .running:
            return WidgetTile(
                status: status,
                statusText: state.endsAt.map { "ends \(clock.string(from: $0))" },
                // The one case that counts itself. Everything else is a still.
                countdown: state.endsAt.map { .interval(now...$0) }
                    ?? .text(ClockFormatter.text(state.remaining(now))),
                progress: state.progress(now),
                caption: state.displayName,
                primary: WidgetControl(title: "Pause", action: .pause),
                secondary: .resetGlyph
            )

        case .paused:
            return WidgetTile(
                status: status,
                // A paused session has no deadline to print (§2.1) and printing the
                // one it will resume to would be inventing a number that goes stale
                // while nothing moves — the window's status line declines for the
                // same reason.
                statusText: "paused",
                countdown: .text(ClockFormatter.text(state.remaining(now))),
                progress: state.progress(now),
                caption: state.displayName,
                primary: WidgetControl(title: "Resume", action: .resume),
                secondary: .resetGlyph
            )

        case .complete:
            return WidgetTile(
                status: status,
                statusText: state.completedAt.map { "ended \(clock.string(from: $0))" },
                countdown: .text(ClockFormatter.text(0)),
                progress: 1,
                // The small card has no room for the span, so it reports the number
                // the summary leads with. The medium's pane carries the rest.
                caption: "Complete · \(minutes(state.focused(now))) min",
                primary: WidgetControl(title: "Start another", action: .start),
                secondary: WidgetControl(title: "+5 min", action: .extend)
            )
        }
    }

    // MARK: Pane

    static func pane(
        for state: SessionState,
        snapshot: CalendarSnapshot?,
        dismissed: Set<String>,
        preferences: Preferences,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> WidgetPane {
        let clock = times.formatter(locale: locale, timeZone: timeZone)

        switch state.effectiveStatus(now) {
        case .idle:
            return .suggestions(
                suggestions(
                    snapshot: snapshot,
                    dismissed: dismissed,
                    preferences: preferences,
                    now: now,
                    calendar: calendar,
                    locale: locale,
                    timeZone: timeZone
                )
            )

        case .running, .paused:
            return .session(
                label: "In session",
                // P5: a session with no stored title shows `25 minute session`, and
                // that string is never written to disk.
                title: state.displayName,
                meta: state.startedAt.map { "Started \(clock.string(from: $0))" }
            )

        case .complete:
            return .session(
                label: "Session complete",
                title: state.displayName,
                // When it started, not the whole summary line. The span and the
                // focused total are §7's "session summary" for the widget, and the
                // card carries both — but split across the two columns, as the
                // mockups draw them: the pane says when the session began and the
                // tile's caption says how much of it was focus. The joined
                // `1:48–2:13 PM · 25 min focused` does not fit 136 pt.
                meta: state.startedAt.map { "Started \(clock.string(from: $0))" }
            )
        }
    }

    /// The idle pane's rows: `45 minutes`, the next half-hour boundary, and the
    /// suggested meeting — the dropdown's list, trimmed to what fits the card.
    ///
    /// The meeting row goes last, as the mockup draws it, because it is the row whose
    /// existence is conditional; putting it first would move the two fixed rows every
    /// time the calendar changed.
    static func suggestions(
        snapshot: CalendarSnapshot?,
        dismissed: Set<String>,
        preferences: Preferences,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [WidgetSuggestion] {
        let suggestion = CalendarDerivations.suggestedEvent(
            in: snapshot,
            dismissed: dismissed,
            buffer: preferences.endEarlyBuffer,
            now: now,
            calendar: calendar
        )

        let meetingRow: WidgetSuggestion? = suggestion.flatMap { event in
            // The buffer is part of the row, not just of the deadline (D7 scopes it
            // to meetings), and `timeableDuration` is the one definition of "worth
            // offering" every surface goes through.
            CalendarDerivations.timeableDuration(
                until: event.startsAt,
                buffer: preferences.endEarlyBuffer,
                now: now
            ).map { duration in
                WidgetSuggestion(
                    id: "event-\(event.id)",
                    title: event.title,
                    metaText: "\(minutes(duration))m",
                    barColorHex: event.colorHex,
                    action: .startMeeting(eventKey: event.id)
                )
            }
        }

        // One fixed length and one clock target: three rows fit the card, and the
        // meeting is the third whenever there is one.
        let durations = ([DurationPreset.fixed] + ClockTarget.next(
            1,
            after: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        ).map(DurationPreset.init)).map { preset in
            WidgetSuggestion(
                id: preset.id,
                title: preset.title,
                metaText: "\(preset.minutes)m",
                barColorHex: nil,
                action: .startDuration(preset.duration)
            )
        }

        // The row that closes the pane: the suggested meeting when there is one, and
        // otherwise empty-calendar copy in place of a blank row (§3.3, and the stage's
        // own bullet). The copy is a row, not an absence.
        let tail = meetingRow ?? WidgetSuggestion(
            id: "calendar-empty",
            title: emptyCalendarCopy,
            metaText: nil,
            barColorHex: nil,
            action: nil
        )

        return exactlyThreeRows(durations + [tail])
    }

    /// The pane's slot count, enforced rather than hoped for.
    ///
    /// Three rows is a geometry commitment: the card does not reflow when a meeting
    /// appears or the clock rolls past the last half-hour boundary of the day, and the
    /// transport below sits where the mockups put it. Trimming to the limit was already
    /// here; *padding* to it was not, and `ClockTarget.next` returning nothing — which
    /// it is entitled to do — would have shipped a two-row pane. A reserved row keeps
    /// its height with nothing in it, exactly as the tile's status row does: no bar (it
    /// carries no action, so `barColor` is already `.clear`), no fill, no title.
    private static func exactlyThreeRows(_ rows: [WidgetSuggestion]) -> [WidgetSuggestion] {
        let limit = DesignTokens.Layout.Widget.suggestionRowLimit
        var rows = Array(rows.prefix(limit))
        while rows.count < limit {
            rows.append(WidgetSuggestion(
                id: "reserved-\(rows.count)",
                title: "",
                metaText: nil,
                barColorHex: nil,
                action: nil
            ))
        }
        return rows
    }

    private static func minutes(_ interval: TimeInterval) -> Int {
        Int((interval / 60).rounded())
    }
}
