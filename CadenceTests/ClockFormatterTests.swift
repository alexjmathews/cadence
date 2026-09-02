import XCTest
@testable import Cadence

/// The one countdown form every surface shares, and the input rules that feed it.
final class ClockFormatterTests: XCTestCase {

    // MARK: - Formatting

    func testTheCountdownIsMinutesAndSeconds() {
        XCTAssertEqual(ClockFormatter.text(0), "00:00")
        XCTAssertEqual(ClockFormatter.text(9), "00:09")
        XCTAssertEqual(ClockFormatter.text(25 * minute), "25:00")
        XCTAssertEqual(ClockFormatter.text(59 * minute + 59), "59:59")
    }

    /// The hour-rollover call this stage makes, and it follows from D9: the numerals
    /// are a minutes field and a seconds field with no hours field to type into, so a
    /// clock that rolled over would render a form its own input cannot express.
    /// Minutes carry past 59 in the countdown exactly as they do in the field.
    func testMinutesCarryPastFiftyNineRatherThanRollingIntoHours() {
        XCTAssertEqual(ClockFormatter.text(60 * minute), "60:00")
        XCTAssertEqual(ClockFormatter.text(90 * minute), "90:00")
        XCTAssertEqual(ClockFormatter.text(ClockFormatter.maximumDuration), "999:59")
    }

    /// What hour rollover was reaching for — 92 pt numerals inside a 520 pt minimum
    /// width — is met by bounding the digits instead.
    func testTheLongestExpressibleDurationIsSixGlyphs() {
        XCTAssertEqual(ClockFormatter.text(ClockFormatter.maximumDuration).count, 6)
    }

    /// Rounded up: a session with a fraction of a second left has not finished, and
    /// the numerals must not say it has before the deadline arrives.
    func testTheRemainderRoundsUpSoZeroMeansFinished() {
        XCTAssertEqual(ClockFormatter.text(0.2), "00:01")
        XCTAssertEqual(ClockFormatter.text(59.5), "01:00")
    }

    /// A wall clock that moved backwards must not print a negative countdown.
    func testANegativeRemainderFloorsAtZero() {
        XCTAssertEqual(ClockFormatter.text(-90), "00:00")
    }

    /// The window splits the same string the dropdown and the status item print
    /// whole — the halves are the formatter's, not a second convention.
    func testTheHalvesComposeBackIntoTheWholeCountdown() {
        for seconds in [0, 9, 59, 60, 25 * 60, 90 * 60, 999 * 60 + 59] {
            let duration = TimeInterval(seconds)
            XCTAssertEqual(
                "\(ClockFormatter.minutesText(duration)):\(ClockFormatter.secondsText(duration))",
                ClockFormatter.text(duration)
            )
        }
    }

    // MARK: - Field input (D9)

    /// Digits and nothing else, refused at input rather than validated afterwards.
    func testANonDigitEntryIsRefused() {
        for entry in ["a", "1a", "-1", "1.5", ":", "1:2", " 1", "1 ", "٣"] {
            XCTAssertNil(
                DurationInput.accepting(entry, .minutes),
                "\(entry.debugDescription) should be refused"
            )
        }
    }

    /// Clearing a field to type a new value is an ordinary thing to do, so an empty
    /// field is accepted and simply reads as zero.
    func testAnEmptyFieldIsAccepted() {
        XCTAssertEqual(DurationInput.accepting("", .minutes), "")
        XCTAssertEqual(DurationInput.accepting("", .seconds), "")
        XCTAssertEqual(DurationInput.duration(minutes: "", seconds: ""), 0)
        XCTAssertEqual(DurationInput.duration(minutes: "", seconds: "30"), 30)
    }

    func testMinutesTakeThreeDigitsAndSecondsTwo() {
        XCTAssertEqual(DurationInput.accepting("999", .minutes), "999")
        XCTAssertNil(DurationInput.accepting("1000", .minutes))
        XCTAssertEqual(DurationInput.accepting("59", .seconds), "59")
        XCTAssertNil(DurationInput.accepting("100", .seconds))
    }

    /// Seconds are clamped to `0…59` by refusing the digit that would break the
    /// bound — the clamp stated at the keystroke instead of at the commit, so the
    /// field never briefly holds a value it will later have to correct.
    func testASecondsEntryPastFiftyNineIsRefused() {
        XCTAssertEqual(DurationInput.accepting("6", .seconds), "6")
        XCTAssertNil(DurationInput.accepting("65", .seconds))
        XCTAssertEqual(DurationInput.accepting("05", .seconds), "05")
        XCTAssertEqual(DurationInput.accepting("00", .seconds), "00")
    }

    /// Minutes carry any value the numerals can draw, which is what makes `90:00` a
    /// legal session rather than an hour and a half the field cannot say.
    func testMinutesCarryAnyValueTheNumeralsCanDraw() {
        XCTAssertEqual(DurationInput.accepting("90", .minutes), "90")
        XCTAssertEqual(
            DurationInput.duration(minutes: "999", seconds: "59"),
            ClockFormatter.maximumDuration
        )
    }

    func testTheFieldsAreSeededWithWhatTheNumeralsAlreadyShow() {
        XCTAssertEqual(DurationInput.minutesText(for: 25 * minute), "25")
        XCTAssertEqual(DurationInput.secondsText(for: 25 * minute), "00")
        XCTAssertEqual(DurationInput.minutesText(for: 5 * minute + 30), "05")
        XCTAssertEqual(DurationInput.secondsText(for: 5 * minute + 30), "30")
        XCTAssertEqual(DurationInput.minutesText(for: 90 * minute), "90")
    }

    /// Every duration the fields can express is one the numerals print back
    /// unchanged — the seed and the commit are inverses.
    func testEveryComposedDurationRoundTripsThroughTheFields() {
        for seconds in [1, 59, 60, 25 * 60, 45 * 60, 90 * 60, 999 * 60 + 59] {
            let duration = TimeInterval(seconds)
            XCTAssertEqual(
                DurationInput.duration(
                    minutes: DurationInput.minutesText(for: duration),
                    seconds: DurationInput.secondsText(for: duration)
                ),
                duration
            )
        }
    }
}
