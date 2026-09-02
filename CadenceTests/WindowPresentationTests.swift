import XCTest
@testable import Cadence

/// The window's pure presentation logic: which contents the fixed swap slot is
/// showing, the `started · ends` line, and the buffer chips.
final class WindowPresentationTests: XCTestCase {

    private func slot(_ state: SessionState, at now: Date) -> WindowSwapSlot {
        WindowSwapSlot.slot(for: state, at: now, locale: Clock.locale, timeZone: Clock.timeZone)
    }

    private func statusLine(_ state: SessionState, at now: Date) -> String? {
        normalizingSpaces(
            WindowStatusLine.text(for: state, at: now, locale: Clock.locale, timeZone: Clock.timeZone)
        )
    }

    // MARK: - Swap slot

    func testIdleOffersTheQuickDurations() {
        XCTAssertEqual(slot(.idle(), at: Clock.at(14, 0)), .durations)
        XCTAssertTrue(slot(.idle(), at: Clock.at(14, 0)).offersDurationSelection)
    }

    /// "The quick durations disappear once a session starts" — the swap slot is the
    /// mechanism, so the presets, the buffer chips and the editable numerals all
    /// leave together.
    func testARunningSessionShowsTheStatusLineInsteadOfTheDurations() {
        let started = Clock.at(14, 2)
        let running = SessionState.running(
            startedAt: started,
            endsAt: Clock.at(14, 27),
            segmentStartedAt: started
        )

        let slot = slot(running, at: Clock.at(14, 12))

        XCTAssertFalse(slot.offersDurationSelection)
        guard case .progress = slot else { return XCTFail("expected the progress slot") }
    }

    func testAPausedSessionKeepsTheProgressSlotAndOffersNoDurations() {
        let paused = SessionState.paused(
            startedAt: Clock.at(14, 2),
            remaining: 10 * minute,
            focusedBefore: 15 * minute
        )

        let slot = slot(paused, at: Clock.at(14, 20))

        XCTAssertFalse(slot.offersDurationSelection)
        guard case .progress = slot else { return XCTFail("expected the progress slot") }
    }

    func testCompleteShowsTheSummary() {
        let complete = SessionState.complete(
            startedAt: Clock.at(13, 48),
            completedAt: Clock.at(14, 13),
            focusedBefore: 25 * minute
        )

        guard case .summary(let line) = slot(complete, at: Clock.at(14, 13)) else {
            return XCTFail("expected the summary slot")
        }
        XCTAssertEqual(normalizingSpaces(line), "1:48–2:13 PM · 25 min focused")
    }

    /// Derived from `effectiveStatus`, never the stored value (D4): a deadline that
    /// passed while nothing was awake shows the summary, not the countdown.
    func testAnElapsedRunningSessionShowsTheSummarySlot() {
        let started = Clock.at(13, 48)
        let running = SessionState.running(
            startedAt: started,
            endsAt: Clock.at(14, 13),
            segmentStartedAt: started
        )

        guard case .summary = slot(running, at: Clock.at(14, 30)) else {
            return XCTFail("expected the summary slot")
        }
    }

    // MARK: - Status line

    func testTheRunningLineNamesBothEndsOfTheSession() {
        let started = Clock.at(14, 2)
        let running = SessionState.running(
            startedAt: started,
            endsAt: Clock.at(14, 27),
            segmentStartedAt: started
        )

        XCTAssertEqual(
            statusLine(running, at: Clock.at(14, 12)),
            "started 2:02 PM · ends 2:27 PM"
        )
    }

    /// A paused session has no deadline (§2.1). It says so rather than printing the
    /// one it would resume to, which does not exist until it resumes.
    func testThePausedLineSaysSoRatherThanInventingADeadline() {
        let paused = SessionState.paused(
            startedAt: Clock.at(14, 2),
            remaining: 10 * minute,
            focusedBefore: 15 * minute
        )

        XCTAssertEqual(statusLine(paused, at: Clock.at(14, 20)), "started 2:02 PM · paused")
    }

    // MARK: - Buffer chips

    func testTheChipsAreTheFourValuesTheStoryOffers() {
        XCTAssertEqual(BufferOption.all.map(\.label), ["off", "1m", "2m", "3m"])
        XCTAssertEqual(BufferOption.all.map(\.seconds), [0, 60, 120, 180])
    }

    func testTheStoredBufferSelectsItsChip() {
        XCTAssertEqual(BufferOption.selected(for: Preferences().endEarlyBuffer)?.label, "2m")
        XCTAssertEqual(BufferOption.selected(for: 0)?.label, "off")
    }

    /// A value the chips do not offer lights up nothing rather than the nearest
    /// thing, so the row never claims a setting the user did not choose.
    func testABufferTheChipsDoNotOfferSelectsNothing() {
        XCTAssertNil(BufferOption.selected(for: 90))
    }
}
