import Foundation

/// The one countdown formatter every surface shares — window numerals, dropdown
/// numerals, and the menu-bar pill.
///
/// **No hour rollover: `MM:SS`, with minutes carrying any value.** `65:00` reads as
/// sixty-five minutes, not `1:05:00`. This follows from D9 rather than from taste:
/// the window's numerals are two fields, minutes and seconds, and there is no hours
/// field to type into. A running clock that rolled over would render a form its own
/// input cannot express — type `90:00` and watch the window answer `1:29:59` — which
/// is exactly the kind of surface-disagreeing-with-itself the model is built to
/// avoid. The minutes field carrying past 59 and the countdown printing past 59 are
/// the same decision.
///
/// The constraint that hour rollover was reaching for — that 92 pt numerals must fit
/// a window whose minimum width is 520 pt — is met by bounding the digits instead:
/// `maximumMinutes` is three digits, so the numerals are never wider than `999:59`.
enum ClockFormatter {
    /// The largest value the minutes field accepts, and so the widest the numerals
    /// can get: six glyphs.
    static let maximumMinutes = 999
    static let maximumSeconds = 59

    /// The longest session the window can express: `999:59`.
    static let maximumDuration = TimeInterval(maximumMinutes * 60 + maximumSeconds)

    /// `MM:SS`, minutes zero-padded to two and never rolled over into hours.
    ///
    /// Rounded *up*, so a session with 200 ms left reads `00:01` rather than
    /// announcing zero before the deadline has actually arrived. Negative input — a
    /// clock that moved backwards — floors at zero.
    static func text(_ remaining: TimeInterval) -> String {
        let total = wholeSeconds(remaining)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// The minutes half of `text`, as the window's minutes field shows it.
    static func minutesText(_ remaining: TimeInterval) -> String {
        String(format: "%02d", wholeSeconds(remaining) / 60)
    }

    /// The seconds half of `text`, as the window's seconds field shows it.
    static func secondsText(_ remaining: TimeInterval) -> String {
        String(format: "%02d", wholeSeconds(remaining) % 60)
    }

    private static func wholeSeconds(_ remaining: TimeInterval) -> Int {
        Int(max(0, remaining).rounded(.up))
    }
}
