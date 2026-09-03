import XCTest
@testable import Cadence

/// What VoiceOver says. Pure string derivations, so they are tested the way every other
/// derivation in `Shared/` is.
///
/// These matter more than they look. The visible clock is `05:00` because the numerals
/// are monospaced and two-digit-padded, and a screen reader given that string says "zero
/// five colon zero zero" — so the spoken form is a *different* rendering of the same
/// value, not a transformation of the visible one, and a bug here is invisible to anyone
/// who is not using the feature.
final class SpokenTextTests: XCTestCase {

    // MARK: - Durations

    func testADurationIsSpokenInWordsRatherThanPaddedDigits() {
        XCTAssertEqual(SpokenText.duration(25 * minute), "25 minutes")
        XCTAssertEqual(SpokenText.duration(5 * minute), "5 minutes")
        XCTAssertEqual(SpokenText.duration(90), "1 minute 30 seconds")
        XCTAssertEqual(SpokenText.duration(45), "45 seconds")
        XCTAssertEqual(SpokenText.duration(60), "1 minute")
        XCTAssertEqual(SpokenText.duration(1), "1 second")
        XCTAssertEqual(SpokenText.duration(61), "1 minute 1 second")
    }

    /// Zero is only ever reached by a session finishing, and "no time remaining" is what
    /// that means. `0 minutes` is a duration; this is a state.
    func testZeroSaysWhatItMeans() {
        XCTAssertEqual(SpokenText.duration(0), "no time remaining")
        XCTAssertEqual(SpokenText.duration(-30), "no time remaining", "a clock that moved backwards")
    }

    /// Three minute digits, which `ClockFormatter` prints and the numerals accept (D9),
    /// stay minutes rather than becoming hours — the spoken form follows the same
    /// no-rollover decision the visible one does, so the two cannot describe the same
    /// session differently.
    func testMinutesCarryPastAnHourJustAsTheNumeralsDo() {
        XCTAssertEqual(SpokenText.duration(90 * minute), "90 minutes")
        XCTAssertEqual(
            SpokenText.duration(ClockFormatter.maximumDuration),
            "999 minutes 59 seconds"
        )
    }

    /// Sub-second values round rather than truncating, so a clock reading `00:01` is never
    /// announced as finished while it is still counting.
    func testSubSecondValuesRoundRatherThanVanishing() {
        XCTAssertEqual(SpokenText.duration(0.6), "1 second")
        XCTAssertEqual(SpokenText.duration(59.7), "1 minute")
    }

    // MARK: - Labels

    /// The label names the *role* and the value carries the time, which is the split
    /// VoiceOver expects: a role read once when focus lands, a value re-read as it moves.
    func testTheClockLabelNamesTheRoleForEachStatus() {
        XCTAssertEqual(SpokenText.clockLabel(for: .idle), "Session duration")
        XCTAssertEqual(SpokenText.clockLabel(for: .running), "Time remaining")
        XCTAssertEqual(SpokenText.clockLabel(for: .paused), "Time remaining, paused")
        XCTAssertEqual(SpokenText.clockLabel(for: .complete), "Session complete")

        // Four statuses, four distinct labels: a surface that read the same sentence in
        // two states would be telling the user nothing about which one it is in.
        let labels: [String] = [SessionStatus.idle, .running, .paused, .complete]
            .map(SpokenText.clockLabel(for:))
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    func testProgressIsWholePercentAndClamped() {
        XCTAssertEqual(SpokenText.progress(0), "0 percent")
        XCTAssertEqual(SpokenText.progress(0.416_666), "42 percent")
        XCTAssertEqual(SpokenText.progress(1), "100 percent")
        XCTAssertEqual(SpokenText.progress(-0.5), "0 percent")
        XCTAssertEqual(SpokenText.progress(1.5), "100 percent")
    }

    /// The chips read `off`, `1m`, `2m`, `3m`; the announcement is what pressing one does.
    func testTheBufferChipsAreSpokenAsWhatTheyDo() {
        XCTAssertEqual(SpokenText.buffer(0), "Do not end early")
        XCTAssertEqual(SpokenText.buffer(60), "End early by 1 minute")
        XCTAssertEqual(SpokenText.buffer(120), "End early by 2 minutes")
        XCTAssertEqual(SpokenText.buffer(180), "End early by 3 minutes")

        // Every chip the window actually offers, so a new one cannot ship unspoken.
        for option in BufferOption.all {
            XCTAssertFalse(SpokenText.buffer(option.seconds).isEmpty)
        }
    }

    // MARK: - Agreement with the visible form

    /// The spoken and the visible clock must describe the same instant. They are derived
    /// independently — one from `ClockFormatter`, one from `SpokenText` — so this is the
    /// only thing holding them together.
    func testTheSpokenClockAndThePrintedClockAgree() {
        for seconds in [0, 1, 59, 60, 61, 90, 1500, 3600, 5999, 59_999] as [TimeInterval] {
            let printed = ClockFormatter.text(seconds)
            let spoken = SpokenText.duration(seconds)

            let parts = printed.split(separator: ":").map { Int($0)! }
            let printedTotal = parts[0] * 60 + parts[1]
            let spokenMinutes = spoken.contains("minute")
                ? Int(spoken.split(separator: " ")[0]) ?? 0
                : 0
            let spokenSeconds: Int = {
                guard let index = spoken.split(separator: " ").firstIndex(where: {
                    $0.hasPrefix("second")
                }) else { return 0 }
                return Int(spoken.split(separator: " ")[index - 1]) ?? 0
            }()

            if seconds > 0 {
                XCTAssertEqual(
                    spokenMinutes * 60 + spokenSeconds, printedTotal,
                    "`\(printed)` and `\(spoken)` are not the same amount of time"
                )
            }
        }
    }
}
