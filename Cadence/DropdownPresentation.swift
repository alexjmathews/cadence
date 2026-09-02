import Foundation

/// A quick-duration row in the dropdown: a fixed length and the two half-hour
/// targets derived from the clock.
///
/// The clock targets are rebuilt on every read rather than cached — `To 2:30`
/// is worth fifteen minutes at 2:15 and two at 2:28, and a stale row would offer
/// a duration the user did not ask for.
struct DurationPreset: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var duration: TimeInterval

    /// Whole minutes, as shown at the trailing edge of the row.
    var minutes: Int { Int((duration / 60).rounded()) }

    /// The fixed length the dropdown always offers, ahead of the clock targets.
    static let fixed = DurationPreset(id: "45m", title: "45 minutes", duration: 45 * 60)

    static func all(
        at now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [DurationPreset] {
        let targets = ClockTarget.next(
            after: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        return [fixed] + targets.map(DurationPreset.init)
    }

    /// A clock target keyed by its boundary, so the row identity survives a tick
    /// that does not change which boundaries are offered.
    init(_ target: ClockTarget) {
        self.init(
            id: "clock-\(Int(target.date.timeIntervalSince1970))",
            title: target.label,
            duration: target.duration
        )
    }

    init(id: String, title: String, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.duration = duration
    }
}

/// The word beside the numerals. Presentation only — a running session shows what
/// it *is* where the other states show where they *are*, which is why this is not
/// simply the status name.
enum StatusWord {
    static func text(for state: SessionState, at now: Date) -> String {
        switch state.effectiveStatus(now) {
        case .idle: "ready"
        case .running: state.title ?? "running"
        case .paused: "paused"
        case .complete: "complete"
        }
    }
}
