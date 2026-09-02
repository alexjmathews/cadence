import Foundation

/// The rules behind the window's two numeral fields (D9).
///
/// There is no grammar here, and that is the point. The numerals are a minutes
/// field and a seconds field with the colon drawn as immovable chrome between them,
/// so a colon cannot be deleted, duplicated or typed; each field holds digits and
/// nothing else. A single free-text field would have to define what `1:2:3::`
/// means — two numeric fields make that state unreachable.
///
/// **Refused at input, not validated afterwards.** `accepting` is asked about every
/// proposed field value *before* it is adopted and answers `nil` when the entry is
/// not one. A refused keystroke leaves the field exactly as it was, so there is no
/// such thing as a malformed entry to reject later, and nothing to explain to the
/// user.
///
/// The asking happens at the **responder** (D9): `NumeralFormatter` hands every
/// proposed field value here before the field editor is allowed to adopt it, which
/// covers typing, paste and IME alike. A SwiftUI `Binding` setter that declines to
/// write is not enough — an `NSTextField` keeps its own live editing text, so a
/// refused keystroke stays on screen while the committed plan silently diverges
/// from it.
///
/// `commitDuration` is the other half of D9's amendment: the commit happens on blur
/// or `Return`, never per keystroke, and never for an empty field.
enum DurationInput {

    /// A field's bound: three digits of minutes, two of seconds.
    struct Field: Equatable, Sendable {
        var digits: Int
        var maximum: Int

        /// Minutes carry any value the numerals can draw (D9).
        static let minutes = Field(digits: 3, maximum: ClockFormatter.maximumMinutes)
        /// Seconds are clamped to `0…59` — by refusing the digit that would break
        /// the bound, which is the same rule stated at the keystroke instead of at
        /// the commit.
        static let seconds = Field(digits: 2, maximum: ClockFormatter.maximumSeconds)
    }

    /// The proposed field text, or `nil` when it is refused.
    ///
    /// An empty field is accepted: clearing minutes to type a new value is an
    /// ordinary thing to do, and an empty field simply reads as zero.
    static func accepting(_ proposed: String, _ field: Field) -> String? {
        guard proposed.count <= field.digits,
              proposed.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        guard !proposed.isEmpty else { return proposed }
        guard let value = Int(proposed), value <= field.maximum else { return nil }
        return proposed
    }

    /// The duration the two fields describe. An empty field reads as zero, so the
    /// pair can be zero in total — which `SessionTransitions.selectDuration`
    /// already refuses, leaving the plan alone until there is a duration to adopt.
    static func duration(minutes: String, seconds: String) -> TimeInterval {
        TimeInterval((Int(minutes) ?? 0) * 60 + (Int(seconds) ?? 0))
    }

    /// The duration a blur or a `Return` should commit, or `nil` when there is
    /// nothing to commit (D9).
    ///
    /// Committing per keystroke walks `plannedDuration` through every intermediate
    /// value — clearing the minutes field to retype it would briefly commit a
    /// 9-second plan to the App Group and reload every widget timeline — so the
    /// commit is deferred to the moment the edit is finished. An **empty** field is
    /// not an edit that finished: it is a field mid-retype, so it commits nothing
    /// and the numerals fall back to the plan they still hold. A pair that composes
    /// to zero commits nothing either, for the same reason
    /// `SessionTransitions.selectDuration` refuses it.
    static func commitDuration(minutes: String, seconds: String) -> TimeInterval? {
        guard !minutes.isEmpty, !seconds.isEmpty else { return nil }
        let duration = duration(minutes: minutes, seconds: seconds)
        return duration > 0 ? duration : nil
    }

    /// The text each field is seeded with: whatever the numerals were already
    /// showing, so editing starts in place rather than from an empty field.
    static func minutesText(for duration: TimeInterval) -> String {
        ClockFormatter.minutesText(duration)
    }

    static func secondsText(for duration: TimeInterval) -> String {
        ClockFormatter.secondsText(duration)
    }
}
