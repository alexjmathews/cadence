import XCTest
@testable import Cadence

/// The `cadence://` grammar.
///
/// A URL is the one input that arrives from outside the app — a Raycast command, a
/// Shortcut, a terminal, a typo — so this is the only parser in the product that has to
/// survive hostile input, and the property that matters is that everything it does not
/// understand does *nothing*. A parser that guessed would start sessions nobody asked
/// for.
final class CadenceURLTests: XCTestCase {

    private func action(_ string: String) -> WidgetAction? {
        guard let url = URL(string: string) else {
            XCTFail("\(string) is not a URL at all")
            return nil
        }
        return CadenceURL.action(for: url)
    }

    // MARK: - The commands

    func testTheFourArgumentlessCommandsParse() {
        XCTAssertEqual(action("cadence://pause"), .pause)
        XCTAssertEqual(action("cadence://resume"), .resume)
        XCTAssertEqual(action("cadence://reset"), .reset)
        XCTAssertEqual(action("cadence://extend"), .extend)
    }

    /// Bare `start` runs the stored plan, which is what the dropdown's own `Start` does.
    /// There is no separate `startAnother`: `start` from `complete` *is* start another,
    /// and the transition's guard is what makes them one action (§5).
    func testBareStartRunsTheStoredPlan() {
        XCTAssertEqual(action("cadence://start"), .start)
        XCTAssertEqual(action("cadence://start?"), .start)
        XCTAssertEqual(
            action("cadence://start?foo=bar"),
            .start,
            "a query with no duration in it is still a request for the stored plan"
        )
    }

    func testAMinutesArgumentBecomesADuration() {
        XCTAssertEqual(action("cadence://start?minutes=45"), .startDuration(45 * minute))
        XCTAssertEqual(action("cadence://start?minutes=1"), .startDuration(minute))
        XCTAssertEqual(
            action("cadence://start?minutes=999"),
            .startDuration(999 * minute),
            "the longest session the numerals can express (D9)"
        )
    }

    func testASecondsArgumentBecomesADuration() {
        XCTAssertEqual(action("cadence://start?seconds=90"), .startDuration(90))
        XCTAssertEqual(action("cadence://start?seconds=1"), .startDuration(1))
    }

    /// Both keys present is a caller that changed its mind mid-string. The coarser one
    /// wins, because it is the one a human typed.
    func testMinutesWinsOverSeconds() {
        XCTAssertEqual(
            action("cadence://start?seconds=30&minutes=45"),
            .startDuration(45 * minute)
        )
    }

    // MARK: - Refusal

    func testAnUnknownSchemeOrHostIsNothing() {
        XCTAssertNil(action("https://start"))
        XCTAssertNil(action("cadence://notify"), "the demo command, deleted in Stage 0")
        XCTAssertNil(action("cadence://startAnother"), "not a command; `start` covers it")
        XCTAssertNil(action("cadence://"))
        XCTAssertNil(action("cadence://start/extra"), "the host is the command, not the path")
    }

    /// Case is not a way to fail. A launcher that title-cased a command, or a scheme
    /// registered as `Cadence`, should still work.
    func testTheSchemeAndCommandAreCaseInsensitive() {
        XCTAssertEqual(action("CADENCE://PAUSE"), .pause)
        XCTAssertEqual(action("cadence://Reset"), .reset)
        XCTAssertEqual(action("cadence://start?MINUTES=45"), .startDuration(45 * minute))
    }

    /// **A duration that was asked for and cannot be honoured is nothing, not a
    /// fallback.** Starting the stored plan instead would silently run a session of a
    /// length the caller did not ask for, which is a worse outcome than a command that
    /// appears to do nothing.
    func testAnUnusableDurationRefusesRatherThanFallingBack() {
        for query in [
            "minutes=0",
            "minutes=-5",
            "minutes=abc",
            "minutes=",
            "minutes=12.5",
            "minutes=1e3",
            "minutes=+5",
            "minutes=1000",           // past `ClockFormatter.maximumMinutes`
            "minutes=45%20min",
            "seconds=0",
            "seconds=-1",
            "seconds=nope",
        ] {
            XCTAssertNil(
                action("cadence://start?\(query)"),
                "`\(query)` must do nothing, not start the stored plan"
            )
        }
    }

    /// The bound is what the surfaces can draw, not an arbitrary sanity limit: the
    /// countdown never rolls over into hours and the minutes field is three digits (D9),
    /// so a longer session is one no surface can express.
    func testTheUpperBoundIsWhatTheNumeralsCanExpress() {
        XCTAssertEqual(
            action("cadence://start?seconds=\(Int(ClockFormatter.maximumDuration))"),
            .startDuration(ClockFormatter.maximumDuration)
        )
        XCTAssertNil(action("cadence://start?seconds=\(Int(ClockFormatter.maximumDuration) + 1)"))
        XCTAssertEqual(ClockFormatter.maximumMinutes, 999)
    }

    /// Whitespace a shell or a launcher may have left in a value.
    func testSurroundingWhitespaceInAValueIsTolerated() {
        XCTAssertEqual(action("cadence://start?minutes=%2045%20"), .startDuration(45 * minute))
    }

    // MARK: - Parity

    /// The URL surface and the widget surface speak the same vocabulary, which is what
    /// makes them one implementation rather than two. Every `cadence://` command must
    /// resolve to an action the widget's own controls already produce — if it did not,
    /// there would be a transition reachable from a launcher and from nowhere else.
    func testEveryCommandResolvesToAnActionTheWidgetAlsoSpeaks() {
        let commands = ["start", "pause", "resume", "reset", "extend"]
        for command in commands {
            guard let resolved = action("cadence://\(command)") else {
                return XCTFail("\(command) did not parse")
            }
            // `Kind` is the wire vocabulary both surfaces flatten to, so a round trip
            // through it is the check that the two agree.
            XCTAssertNotNil(
                WidgetAction(kind: resolved.kind.rawValue, duration: 0, eventKey: ""),
                "\(command) resolves to something the widget's wire form cannot carry"
            )
        }

        // And the one command that carries an argument.
        XCTAssertEqual(
            action("cadence://start?minutes=45")?.kind,
            WidgetAction.Kind.startDuration
        )
    }

    /// `startMeeting` is deliberately absent. It needs an occurrence key, which is an
    /// opaque identity string a launcher has no way to obtain and no business
    /// constructing; the meeting rows in the dropdown, the window strip and the medium
    /// widget are where that action lives.
    func testThereIsNoURLPathToAMeetingStart() {
        XCTAssertNil(action("cadence://startMeeting?eventKey=whatever"))
        // And `start` does not grow one by being handed a key. Unknown query keys are
        // ignored rather than refused — a launcher appending its own tracking parameter
        // should not break a command — so this is the plain stored plan, which is the
        // point: no reading of a URL reaches a meeting-linked start.
        XCTAssertEqual(action("cadence://start?eventKey=whatever"), .start)
    }
}
