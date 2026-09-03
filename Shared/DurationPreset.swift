import Foundation

/// A quick-duration row: a fixed length and the two half-hour targets derived from
/// the clock.
///
/// In `Shared/` rather than beside the dropdown because the medium widget offers the
/// same three rows from the extension's process, and two definitions of "45 minutes"
/// is how the two surfaces come to disagree about what a preset is worth.
///
/// The clock targets are rebuilt on every read rather than cached — `To 2:30`
/// is worth fifteen minutes at 2:15 and two at 2:28, and a stale row would offer
/// a duration the user did not ask for.
struct DurationPreset: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    /// The chip form. The dropdown gives each preset a full row and spells it out;
    /// the window packs the same three into one 62 pt slot, where `45 minutes` is a
    /// third wider than the two clock targets it sits beside for no extra meaning.
    var shortTitle: String
    var duration: TimeInterval

    /// Whole minutes, as shown at the trailing edge of the row.
    var minutes: Int { Int((duration / 60).rounded()) }

    /// The fixed length the dropdown always offers, ahead of the clock targets.
    static let fixed = DurationPreset(
        id: "45m",
        title: "45 minutes",
        shortTitle: "45 min",
        duration: 45 * 60
    )

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
    /// that does not change which boundaries are offered. `To 2:30` is already as
    /// short as it gets, so the chip and the row read the same.
    init(_ target: ClockTarget) {
        self.init(
            id: "clock-\(Int(target.date.timeIntervalSince1970))",
            title: target.label,
            shortTitle: target.label,
            duration: target.duration
        )
    }

    init(id: String, title: String, shortTitle: String? = nil, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle ?? title
        self.duration = duration
    }
}
