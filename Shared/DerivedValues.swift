import Foundation

/// Values computed from `SessionState` and an injected `now`. None of these is
/// ever stored: a second copy of the truth is a copy that can disagree with the
/// deadline (P1).
extension SessionState {
    /// The only status a surface should read (D4). A session whose deadline passed
    /// while nothing was awake to transition it still reads as complete.
    func effectiveStatus(_ now: Date) -> SessionStatus {
        if status == .running, let endsAt, endsAt <= now { return .complete }
        return status
    }

    /// Time left on the clock. Derived from the deadline while running, from the
    /// frozen remainder while paused, and from the plan while idle.
    func remaining(_ now: Date) -> TimeInterval {
        switch effectiveStatus(now) {
        case .idle: plannedDuration
        case .running: max(0, (endsAt ?? now).timeIntervalSince(now))
        case .paused: self.remaining ?? 0
        case .complete: 0
        }
    }

    /// Time actually spent running, which pauses make differ from the span.
    /// Capped at the plan so an over-run cannot report more focus than was asked
    /// for, and floored at zero against a backwards wall clock.
    func focused(_ now: Date) -> TimeInterval {
        let current = segmentStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return min(max(0, focusedBefore + current), max(0, plannedDuration))
    }

    /// Fraction of the plan elapsed, clamped. Freezes while paused because
    /// `remaining` is frozen.
    func progress(_ now: Date) -> Double {
        guard plannedDuration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(now) / plannedDuration))
    }

    /// The name shown wherever the session appears. Presentation only — the
    /// fallback is never written to disk (P5).
    var displayName: String {
        title ?? "\(Int(plannedDuration / 60)) minute session"
    }

    /// The wall-clock span of a finished session, available once it has both a
    /// start and a completion.
    var span: ClosedRange<Date>? {
        guard let startedAt, let completedAt, startedAt <= completedAt else { return nil }
        return startedAt...completedAt
    }

    /// The span as shown in the summary, e.g. `1:48–2:13 PM`. The day period is
    /// printed once when both ends share it.
    func spanText(locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        guard let span else { return nil }
        let time = SessionState.formatter(template: "jmm", locale: locale, timeZone: timeZone)
        let period = SessionState.formatter(template: "a", locale: locale, timeZone: timeZone)

        var lower = time.string(from: span.lowerBound)
        let upper = time.string(from: span.upperBound)
        let lowerPeriod = period.string(from: span.lowerBound)
        if !lowerPeriod.isEmpty, lowerPeriod == period.string(from: span.upperBound) {
            lower = lower
                .replacingOccurrences(of: lowerPeriod, with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        return "\(lower)–\(upper)"
    }

    /// The one retrospective view in the product: when the session ran, and how
    /// much of it was spent running.
    func summaryLine(_ now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        guard let spanText = spanText(locale: locale, timeZone: timeZone) else { return nil }
        return "\(spanText) · \(Int(focused(now) / 60)) min focused"
    }

    private static func formatter(
        template: String,
        locale: Locale,
        timeZone: TimeZone
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}

/// A "run until the next half hour" preset, e.g. `To 2:30` at 22 minutes.
struct ClockTarget: Equatable, Sendable {
    var date: Date
    var duration: TimeInterval
    var label: String

    /// Whole minutes to the target, as shown beside the label.
    var minutes: Int { Int((duration / 60).rounded()) }

    /// The next `count` half-hour boundaries strictly after `now + lead`. The lead
    /// keeps a target that is about to pass out of the list.
    static func next(
        _ count: Int = 2,
        after now: Date,
        lead: TimeInterval = 5 * 60,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [ClockTarget] {
        guard count > 0 else { return [] }
        let earliest = now.addingTimeInterval(lead)
        let step: TimeInterval = 30 * 60
        let hour = calendar.dateInterval(of: .hour, for: earliest)?.start ?? earliest

        var boundary = hour
        while boundary <= earliest { boundary.addTimeInterval(step) }

        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.setLocalizedDateFormatFromTemplate("jmm")
        let period = DateFormatter()
        period.locale = locale
        period.timeZone = timeZone
        period.setLocalizedDateFormatFromTemplate("a")

        return (0..<count).map { index in
            let date = boundary.addingTimeInterval(step * Double(index))
            // The label reads "To 2:30": the boundary is close enough that the
            // day period would only add noise.
            var clock = time.string(from: date)
            let dayPeriod = period.string(from: date)
            if !dayPeriod.isEmpty {
                clock = clock
                    .replacingOccurrences(of: dayPeriod, with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            return ClockTarget(
                date: date,
                duration: date.timeIntervalSince(now),
                label: "To \(clock)"
            )
        }
    }
}

extension CalendarSnapshot {
    /// False means show the empty state — never yesterday's meetings.
    func isFresh(_ now: Date, calendar: Calendar = .current) -> Bool {
        day == calendar.startOfDay(for: now)
    }
}

/// The calendar-dependent derivations (§4). They take the snapshot, the dismissal
/// set and `now` as arguments rather than reading a store, so they are pure and the
/// app and the widget compute the same suggestion from the same record.
enum CalendarDerivations {
    /// A suggestion has to still be worth offering: below this the session would be
    /// over before the user let go of the mouse. §4 writes it as
    /// `startsAt − buffer > now + 1 min`.
    static let minimumLead: TimeInterval = 60

    /// The first event that is neither dismissed nor too close to be worth timing
    /// against (§4).
    ///
    /// The buffer is part of the test, not just of the deadline: an event 90 seconds
    /// away with a 2 minute buffer would yield a *negative* duration, and offering
    /// it would be offering a timer that has already finished.
    ///
    /// A snapshot for another day suggests nothing. It is the same test the day list
    /// applies and the store applies on read, repeated here because "never yesterday's
    /// meetings" (§2.3) should not depend on which of three callers remembered it.
    static func suggestedEvent(
        in snapshot: CalendarSnapshot?,
        dismissed: Set<String>,
        buffer: TimeInterval,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> EventOccurrence? {
        guard let snapshot,
              snapshot.access == .authorized,
              snapshot.isFresh(now, calendar: calendar)
        else { return nil }
        return snapshot.events.first { event in
            guard !dismissed.contains(event.id) else { return false }
            return timeableDuration(until: event.startsAt, buffer: buffer, now: now) != nil
        }
    }

    /// `status == .idle && suggestedEvent != nil` (§4). `complete` is deliberately
    /// not included: §5 makes `startAnother` legal there, but the strip's action is
    /// the *idle* offer, and the mockups draw no meeting action over the mint shell.
    static func canStartMeetingTimer(
        for state: SessionState,
        suggestion: EventOccurrence?,
        now: Date
    ) -> Bool {
        state.effectiveStatus(now) == .idle && suggestion != nil
    }

    /// The session length a meeting-linked start would materialise: from `now` to
    /// the event's start, less the buffer (§2.2, P4).
    ///
    /// `nil` when that is not a session anyone would want — the event has begun, or
    /// the buffer has eaten what was left. The caller starts nothing rather than
    /// starting something absurd.
    static func meetingDuration(
        until startsAt: Date,
        buffer: TimeInterval,
        now: Date
    ) -> TimeInterval? {
        let duration = startsAt.addingTimeInterval(-max(0, buffer)).timeIntervalSince(now)
        return duration > 0 ? duration : nil
    }

    /// `meetingDuration` held to §4's one threshold: a session worth *offering*, not
    /// merely one with a positive length.
    ///
    /// This is the single definition of "worth timing against", and every surface
    /// that offers a meeting-linked start goes through it — the strip's action, the
    /// day list's `Start 120m`, and the press itself. Two surfaces disagreeing about
    /// it is how the day list came to offer `Start 0m` for an event twenty seconds
    /// past the buffer while the strip correctly offered nothing.
    static func timeableDuration(
        until startsAt: Date,
        buffer: TimeInterval,
        now: Date
    ) -> TimeInterval? {
        guard let duration = meetingDuration(until: startsAt, buffer: buffer, now: now),
              duration > minimumLead
        else { return nil }
        return duration
    }
}
