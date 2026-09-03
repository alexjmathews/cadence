import Foundation

/// What the window's fixed-height swap slot is showing (§3.1). Selecting the
/// contents is pure logic over the session and the clock, so the rule "quick
/// durations disappear once a session starts" is a testable fact rather than a
/// branch buried in a view body.
enum WindowSwapSlot: Equatable, Sendable {
    /// Idle: quick durations and the end-early buffer chips.
    case durations
    /// Running or paused: the progress rule and the `started · ends` line.
    case progress(statusLine: String)
    /// Complete: the progress rule, the heading, and the session summary.
    case summary(line: String?)

    /// Derived from `effectiveStatus`, never the stored value (D4).
    static func slot(
        for state: SessionState,
        at now: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> WindowSwapSlot {
        switch state.effectiveStatus(now) {
        case .idle:
            return .durations
        case .running, .paused:
            return .progress(
                statusLine: WindowStatusLine.text(
                    for: state,
                    at: now,
                    locale: locale,
                    timeZone: timeZone
                )
            )
        case .complete:
            return .summary(
                line: state.summaryLine(now, locale: locale, timeZone: timeZone)
            )
        }
    }

    /// Whether duration selection is on offer — the presets, the buffer chips, and
    /// the editable numerals alike. Legal only in `idle` (§5 third guard).
    var offersDurationSelection: Bool { self == .durations }
}

/// `started 2:02 PM · ends 2:27 PM` — the line under the progress rule.
///
/// A paused session has no deadline to print (§2.1), so it says so rather than
/// inventing one from the frozen remainder: the deadline it will resume to does not
/// exist yet, and printing a guess would be the one number on the window that goes
/// stale while nothing moves.
enum WindowStatusLine {
    /// The line is rebuilt on every tick of the 1 s display ticker (D1), and a
    /// `DateFormatter` is expensive enough that building one per second to print two
    /// times that change once a minute is worth not doing. Keyed by locale and time
    /// zone because both are arguments here — the tests inject a fixed pair.
    private static let formatters = FormatterCache(template: "jmm")

    static func text(
        for state: SessionState,
        at now: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = formatters.formatter(locale: locale, timeZone: timeZone)

        let started = state.startedAt.map { "started \(formatter.string(from: $0))" }
        let tail: String? = switch state.effectiveStatus(now) {
        case .running: state.endsAt.map { "ends \(formatter.string(from: $0))" }
        case .paused: "paused"
        default: nil
        }

        return [started, tail].compacted.joined(separator: " · ")
    }
}

/// The end-early buffer as the window offers it: `off`, `1m`, `2m`, `3m` (§2.2).
///
/// The chips write `preferences.endEarlyBuffer` and nothing else. Per D7 the buffer
/// never touches a clock target — `To 2:30` ends at 2:30 — so changing it while a
/// session runs retimes nothing, which is exactly what §2.2 promises.
struct BufferOption: Equatable, Identifiable, Sendable {
    var seconds: TimeInterval
    var label: String

    var id: TimeInterval { seconds }

    static let all: [BufferOption] = [
        BufferOption(seconds: 0, label: "off"),
        BufferOption(seconds: 60, label: "1m"),
        BufferOption(seconds: 120, label: "2m"),
        BufferOption(seconds: 180, label: "3m"),
    ]

    /// The chip a stored preference lights up. A value the chips do not offer —
    /// written by a future settings surface, or decoded from an older record —
    /// lights up nothing rather than the wrong thing.
    static func selected(for buffer: TimeInterval) -> BufferOption? {
        all.first { $0.seconds == buffer }
    }
}

private extension Array where Element == String? {
    /// `compactMap { $0 }` reads worse than the intent at the call site.
    var compacted: [String] { compactMap { $0 } }
}

/// `DateFormatter`s kept alive across renders, one per locale and time zone. Shared
/// by every surface that prints a time — the status line, the calendar strip, and the
/// day list — because building one per second to print times that change once a
/// minute is worth not doing.
///
/// `@unchecked Sendable` is earned by the lock: every access to the dictionary is
/// inside it, and a `DateFormatter` handed out is only ever read.
final class FormatterCache: @unchecked Sendable {
    private let template: String
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    init(template: String) {
        self.template = template
    }

    func formatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let key = "\(locale.identifier)|\(timeZone.identifier)"

        lock.lock()
        defer { lock.unlock() }
        if let cached = formatters[key] { return cached }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter
    }
}
