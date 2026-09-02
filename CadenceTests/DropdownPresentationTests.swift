import XCTest
@testable import Cadence

/// The dropdown's two pieces of pure presentation logic: what the quick-duration
/// rows offer, and the word beside the numerals.
final class DropdownPresentationTests: XCTestCase {

    /// Built against the fixture clock's zone so the boundary labels read as the
    /// afternoon the other suites are written in.
    private func presets(at now: Date) -> [DurationPreset] {
        DurationPreset.all(
            at: now,
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )
    }

    // MARK: - Presets

    func testPresetsAreTheFixedLengthThenTheTwoClockTargets() {
        let now = Clock.at(14, 13)

        let presets = presets(at: now)

        XCTAssertEqual(presets.count, 3)
        XCTAssertEqual(presets[0].title, "45 minutes")
        XCTAssertEqual(presets[0].duration, 45 * minute)
        XCTAssertEqual(presets[1].title, "To 2:30")
        XCTAssertEqual(presets[2].title, "To 3:00")
    }

    /// The trailing label is the honest distance to the boundary, so `To 2:30` at
    /// 2:13 is worth seventeen minutes and not a rounded fifteen.
    func testClockTargetRowsCarryTheirWholeMinutesToTheBoundary() {
        let presets = presets(at: Clock.at(14, 13))

        XCTAssertEqual(presets[1].duration, 17 * minute)
        XCTAssertEqual(presets[1].minutes, 17)
        XCTAssertEqual(presets[2].minutes, 47)
    }

    /// The five-minute lead keeps a boundary that is about to pass out of the list,
    /// so a row is never worth less than it takes to read it.
    func testAClockTargetInsideTheLeadIsSkipped() {
        let presets = presets(at: Clock.at(14, 28))

        XCTAssertEqual(presets[1].title, "To 3:00")
        XCTAssertEqual(presets[2].title, "To 3:30")
    }

    /// Row identity is the boundary, not the position, so a tick that leaves the
    /// same two boundaries on offer does not re-create the rows.
    func testClockTargetIdentityIsStableAcrossTicksWithinTheSameBoundaries() {
        let first = presets(at: Clock.at(14, 13))
        let second = presets(at: Clock.at(14, 14))

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertNotEqual(first[1].duration, second[1].duration)
    }

    func testMinutesRoundsRatherThanTruncates() {
        XCTAssertEqual(DurationPreset(id: "x", title: "x", duration: 89).minutes, 1)
        XCTAssertEqual(DurationPreset(id: "x", title: "x", duration: 91).minutes, 2)
    }

    // MARK: - Status word

    func testStatusWordNamesTheStateExceptWhileRunning() {
        let now = Clock.at(14, 0)

        XCTAssertEqual(StatusWord.text(for: .idle(), at: now), "ready")
        XCTAssertEqual(
            StatusWord.text(
                for: .paused(startedAt: Clock.at(13, 48), remaining: 10 * minute, focusedBefore: 0),
                at: now
            ),
            "paused"
        )
        XCTAssertEqual(
            StatusWord.text(
                for: .complete(
                    startedAt: Clock.at(13, 48),
                    completedAt: Clock.at(14, 13),
                    focusedBefore: 25 * minute
                ),
                at: now
            ),
            "complete"
        )
    }

    /// A running session shows what it *is*; only an unnamed one falls back to
    /// where it is. The fallback is the word, not `displayName` — the numerals
    /// beside it already say how long the session is.
    func testARunningSessionShowsItsTitleAndOtherwiseTheWord() {
        let now = Clock.at(14, 0)
        let running = SessionState.running(
            title: "Design review",
            startedAt: now,
            endsAt: now.addingTimeInterval(25 * minute),
            segmentStartedAt: now
        )

        XCTAssertEqual(StatusWord.text(for: running, at: now), "Design review")

        var unnamed = running
        unnamed.title = nil
        XCTAssertEqual(StatusWord.text(for: unnamed, at: now), "running")
    }

    /// Derived, never stored (D4): a session whose deadline passed while nothing
    /// was awake reads as complete, title or no title.
    func testAnElapsedDeadlineReadsAsCompleteRatherThanItsTitle() {
        let started = Clock.at(13, 48)
        let running = SessionState.running(
            title: "Design review",
            startedAt: started,
            endsAt: Clock.at(14, 13),
            segmentStartedAt: started
        )

        XCTAssertEqual(StatusWord.text(for: running, at: Clock.at(14, 20)), "complete")
    }
}
