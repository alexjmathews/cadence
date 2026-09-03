import Foundation

/// What VoiceOver says, for the things whose visible label is an abbreviation.
///
/// **Why this is a file and not a modifier per view.** Most of Cadence's controls are
/// `Button("Pause")` and read correctly as they are; a handful are deliberately terse
/// because the surface is 272 pt wide or a 170 pt card — `45 min`, `2m`, `↺`, `00:00`
/// — and an abbreviation is a design decision about the *visible* label, not about what
/// the control is. Spelling those out in each view body would put the same sentence in
/// the window, the dropdown and the widget with three chances to drift, and the whole
/// point of `Shared/` is that four surfaces cannot disagree.
///
/// It is also where the clock's spoken form belongs. `ClockFormatter` prints `05:00`
/// because the numerals are monospaced and two-digit-padded; VoiceOver reading
/// "zero five colon zero zero" is a worse experience than the sighted one, so the clock
/// is announced in words and the padding is a fact about the glyphs only.
enum SpokenText {

    /// A duration in words: `25 minutes`, `1 minute 30 seconds`, `45 seconds`.
    ///
    /// Zero is `no time remaining` rather than `0 minutes`, because it is only ever
    /// reached by a session finishing and "no time remaining" is what that means.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        guard total > 0 else { return "no time remaining" }

        let minutes = total / 60
        let remainder = total % 60

        switch (minutes, remainder) {
        case (0, let s):
            return "\(s) second\(s == 1 ? "" : "s")"
        case (let m, 0):
            return "\(m) minute\(m == 1 ? "" : "s")"
        case (let m, let s):
            return "\(m) minute\(m == 1 ? "" : "s") \(s) second\(s == 1 ? "" : "s")"
        }
    }

    /// The clock, as the surface it sits on means it. The label names the *role* and
    /// the value carries the time, which is the split VoiceOver expects: the role is
    /// read once when focus lands and the value is re-read as it changes.
    static func clockLabel(for status: SessionStatus) -> String {
        switch status {
        case .idle: "Session duration"
        case .running: "Time remaining"
        case .paused: "Time remaining, paused"
        case .complete: "Session complete"
        }
    }

    /// The progress rule. It is a rule, not a control, so it gets a value and no hint —
    /// there is nothing to do to it.
    ///
    /// Rounded to whole percent: `progress` is a continuous derivation and announcing
    /// `41.6666 percent` would be a worse reading of the same fact.
    static func progress(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded())) percent"
    }

    /// The end-early buffer chips, whose visible labels are `off`, `1m`, `2m`, `3m`.
    static func buffer(_ seconds: TimeInterval) -> String {
        seconds <= 0
            ? "Do not end early"
            : "End early by \(duration(seconds))"
    }
}
