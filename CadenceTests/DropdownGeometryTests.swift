import AppKit
import SwiftUI
import XCTest
@testable import Cadence

/// D10 on the two menu-bar surfaces, measured rather than asserted.
///
/// **Why this suite exists.** The dropdown rendered a sixty-minute meeting-linked
/// session as `60:...` — the numerals and the session title share a row, and the title
/// won. Every presentation test stayed green, because `clockText` was `60:00` the whole
/// time; the string was right and the *layout* threw two glyphs away. So the only test
/// that can hold this rule is one that renders the real row at the real width and looks
/// at where the ink is.
///
/// The measurement is the same one `WidgetGeometryTests` takes: render at 2×, walk the
/// alpha channel, and report the bounding box of every pixel the view painted.
@MainActor
final class DropdownGeometryTests: XCTestCase {

    /// A title long enough that nothing sensible fits beside six numerals, which is the
    /// case that broke. Generic — the real one was a meeting name.
    private static let longTitle = "Quarterly planning review with the platform group"

    // MARK: - Measurement

    /// The bounding box, in points, of every pixel the view painted at or above
    /// `minimumAlpha`. The views draw no background of their own here, so "content" is
    /// "not transparent" and the box can be measured without knowing a single colour.
    ///
    /// **`minimumAlpha` is how the clock is separated from the label beside it.** A
    /// bounding box is a union, and the title's ink reaches the far edge of the sheet
    /// either way — so a box measured over everything cannot tell a whole clock from a
    /// truncated one, and an earlier version of this suite passed against the very
    /// defect it was written for. But §1.3 draws the clock at `TextColor.primary`, which
    /// is opaque, and the status word at `secondary`, which is 58%: over transparency
    /// their premultiplied alphas are 255 and 148, so a threshold between the two
    /// isolates the numerals *inside the real row* rather than in a copy of it.
    ///
    /// It holds for `idle`, `running` and `paused`. It does **not** hold for `complete`,
    /// where §1.2 gives both the clock and the word the same opaque `completeText` — so
    /// the isolating assertions are taken in `running`, which is also the state D10's
    /// defect appeared in, because that is the state whose word is a session title.
    private func contentBounds(
        of view: some View,
        width: CGFloat,
        minimumAlpha: UInt8 = 8
    ) throws -> CGRect {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "the view produced no render")

        let pixelWidth = image.width
        let pixelHeight = image.height
        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        var minX = pixelWidth, maxX = -1, minY = pixelHeight, maxY = -1
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth where pixels[(y * pixelWidth + x) * 4 + 3] > minimumAlpha {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, 0, "the render is entirely transparent")

        return CGRect(
            x: CGFloat(minX) / renderer.scale,
            y: CGFloat(minY) / renderer.scale,
            width: CGFloat(maxX - minX + 1) / renderer.scale,
            height: CGFloat(maxY - minY + 1) / renderer.scale
        )
    }

    /// The width a string's ink occupies at a given face, with nothing competing with
    /// it. Every "was it truncated?" assertion is a comparison against this.
    private func inkWidth(_ text: String, font: Font, tracking: CGFloat = 0) throws -> CGFloat {
        try contentBounds(
            of: Text(text)
                .font(font)
                .tracking(tracking)
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .fixedSize(),
            width: 600
        ).width
    }

    /// The same, at the dropdown's numeral face.
    private func clockInkWidth(_ text: String) throws -> CGFloat {
        try inkWidth(
            text,
            font: DesignTokens.Typography.dropdownNumerals,
            tracking: DesignTokens.Typography.dropdownNumeralsTracking
        )
    }

    /// The numerals' ink *inside the real header row*, isolated from the label by alpha.
    private func clockInk(
        _ clock: String,
        beside word: String,
        width: CGFloat = DesignTokens.Layout.dropdownWidth
    ) throws -> CGRect {
        try contentBounds(
            of: MenuBarDropdown.DropdownHeader(
                clockText: clock,
                statusWord: word,
                status: .running
            ),
            width: width,
            // Above the status word's 58%, below the numerals' opaque.
            minimumAlpha: 200
        )
    }

    // MARK: - Dropdown

    /// The defect, as a test: six numerals beside a long title, at the sheet's own
    /// width. The clock's ink must be as wide as the clock's ink is when nothing is
    /// competing with it — which is what "never compressed, ellipsed, or truncated"
    /// means when you can only see pixels.
    ///
    /// The label is measured too, because the *other* half of D10 is that the title
    /// yields: a row where neither text fits and both are clipped would pass a
    /// clock-only assertion.
    func testTheWidestClockSurvivesALongTitleInTheSheet() throws {
        let width = DesignTokens.Layout.dropdownWidth
        let padding = DesignTokens.Layout.Dropdown.horizontalPadding
        let expected = try clockInkWidth(DesignTokens.Clock.widest)

        // The clock's own ink, inside the real row, beside a title far too long to fit.
        let clock = try clockInk(DesignTokens.Clock.widest, beside: Self.longTitle)
        // The tolerance is the glyph's left side bearing: ink starts inside its own
        // advance, and this measures ink. At 38 pt the monospaced digits sit about
        // 2.5 pt in, which is a fact about the face and not slack in the assertion —
        // a clock on the wrong column would be out by the 16 pt padding itself.
        XCTAssertEqual(clock.minX, padding, accuracy: 4, "the clock starts on the text column")
        XCTAssertEqual(
            clock.width, expected, accuracy: 2,
            """
            the clock was compressed: \(clock.width) pt of ink where \(expected) pt is \
            the whole of it. This is the D10 defect — the numerals and the title share a \
            row and the title won.
            """
        )

        // And the row as a whole stays inside the sheet's text column, which is the other
        // half of the rule: the title yields rather than overrunning.
        let row = try contentBounds(
            of: MenuBarDropdown.DropdownHeader(
                clockText: DesignTokens.Clock.widest,
                statusWord: Self.longTitle,
                status: .running
            ),
            width: width
        )
        XCTAssertLessThanOrEqual(
            row.maxX, width - padding + 1,
            "the row overran the sheet's text column"
        )
    }

    /// Every clock the formatter can print, in the row that broke. Parameterised because
    /// the fault was width-dependent and only the widest form showed it.
    func testEveryClockWidthSurvivesALongTitle() throws {
        let padding = DesignTokens.Layout.Dropdown.horizontalPadding

        for text in ["00:00", "05:00", "25:00", "60:00", "999:59", DesignTokens.Clock.widest] {
            let expected = try clockInkWidth(text)
            let clock = try clockInk(text, beside: Self.longTitle)
            XCTAssertEqual(clock.minX, padding, accuracy: 4, "\(text) does not start on the column")
            XCTAssertEqual(
                clock.width, expected, accuracy: 2,
                "\(text) was compressed beside a long title: \(clock.width) of \(expected) pt"
            )
        }
    }

    /// The arithmetic behind the width, so a future change to the sheet or to the
    /// numerals' size fails here rather than on screen.
    ///
    /// `clockReservedWidth` is a *measured* constant, and this is what keeps it honest:
    /// the real face is re-measured every run, so a system whose monospaced digits are
    /// wider fails the suite instead of shipping a clipped clock.
    func testTheSheetIsWideEnoughForTheWidestClockBesideAStatusWord() throws {
        typealias Sheet = DesignTokens.Layout.Dropdown

        let measured = try clockInkWidth(DesignTokens.Clock.widest)
        XCTAssertLessThanOrEqual(
            measured, Sheet.clockReservedWidth,
            "the widest clock no longer fits the column reserved for it"
        )

        // The four bare status words are chrome, not content, and must never truncate —
        // only *titles* do (D10).
        for word in ["ready", "running", "paused", "complete"] {
            let ink = try contentBounds(
                of: Text(word)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(Color.white)
                    .fixedSize(),
                width: 400
            ).width
            XCTAssertLessThanOrEqual(
                ink, Sheet.statusWordMinimumWidth,
                "`\(word)` does not fit the column reserved for the status word"
            )
        }

        XCTAssertGreaterThanOrEqual(
            DesignTokens.Layout.dropdownWidth, Sheet.minimumWidth,
            "the sheet is narrower than the widest clock plus an untruncated status word"
        )
    }

    /// The status word yields, which is the other half of the rule. A title that cannot
    /// fit is truncated — so its ink must stop short of the sheet's own text column
    /// rather than running under the edge.
    func testTheTitleTruncatesRatherThanOverrunningTheSheet() throws {
        let width = DesignTokens.Layout.dropdownWidth
        let padding = DesignTokens.Layout.Dropdown.horizontalPadding

        let row = try contentBounds(
            of: MenuBarDropdown.DropdownHeader(
                clockText: DesignTokens.Clock.widest,
                statusWord: Self.longTitle,
                status: .running
            ),
            width: width
        )
        XCTAssertLessThanOrEqual(
            row.maxX, width - padding + 1,
            "the title ran past the text column instead of truncating"
        )
        // The title *is* still drawn — "truncates" is not "disappears". Its ink is
        // everything the row paints beyond the clock's own right edge.
        let clock = try clockInk(DesignTokens.Clock.widest, beside: Self.longTitle)
        XCTAssertGreaterThan(
            row.maxX, clock.maxX + DesignTokens.Layout.Dropdown.controlPadding,
            "the title was squeezed out of the row entirely"
        )
    }

    // MARK: - Status pill

    /// The pill reserves a clock column rather than hugging its digits, so the item does
    /// not walk along the menu bar as a session crosses 100 minutes. Both halves of that
    /// are measurable: the widest clock is inside the chip, and every clock produces the
    /// same chip.
    func testThePillHoldsTheWidestClockAndOneWidth() throws {
        var widths: Set<CGFloat> = []

        for text in ["00:00", "25:00", "600:00", "999:59"] {
            let pill = StatusPill(clockText: text, status: .running)
            let renderer = ImageRenderer(content: pill)
            renderer.scale = 2
            let size = try XCTUnwrap(renderer.nsImage?.size, "the pill produced no render")

            widths.insert(size.width.rounded())
            XCTAssertEqual(
                size.height.rounded(),
                DesignTokens.Layout.StatusItem.pillHeight.rounded(),
                "\(text): the pill is not the height the mockups measure"
            )
        }

        XCTAssertEqual(
            widths.count, 1,
            "the pill changes width with the clock: \(widths.sorted())"
        )
        XCTAssertEqual(
            widths.first, DesignTokens.Layout.StatusItem.pillWidth.rounded(),
            "the rendered pill is not the width its tokens compose to"
        )
    }

    /// And the clock inside it is not compressed: its ink must be the same width in the
    /// pill as it is on its own.
    func testThePillDoesNotCompressTheWidestClock() throws {
        let alone = try contentBounds(
            of: Text(DesignTokens.Clock.widest)
                .font(DesignTokens.Typography.listTime)
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .fixedSize(),
            width: 200
        )
        XCTAssertLessThanOrEqual(
            alone.width,
            DesignTokens.Layout.StatusItem.pillClockWidth,
            "the widest clock no longer fits the pill's reserved column"
        )
    }

    // MARK: - Window

    /// The window's 92 pt numerals against three minute digits — the one check the plan
    /// asks for on that surface.
    ///
    /// §3.2 makes the halves equal-width columns either side of a colon on the centre
    /// line, so the widest clock the window can draw is two columns plus the colon's own
    /// advance, and that has to fit the content column at the window's **minimum** width
    /// or a three-digit session pushes its own numerals under the frame.
    func testTheWindowNumeralsFitThreeMinuteDigitsAtTheMinimumWidth() throws {
        typealias Row = DesignTokens.Layout.WindowRow

        let face = DesignTokens.Typography.windowNumerals
        let tracking = DesignTokens.Typography.windowNumeralsTracking

        // The measured constants, re-measured.
        XCTAssertLessThanOrEqual(
            try inkWidth("600", font: face, tracking: tracking), Row.numeralColumnWidth,
            "three minute digits no longer fit one numeral column"
        )
        XCTAssertLessThanOrEqual(
            // The colon carries no tracking: its ink is centred in its own advance,
            // which is what puts it on the window's centre line (§3.2).
            try inkWidth(":", font: face), Row.numeralColonWidth,
            "the colon is wider than the advance reserved for it"
        )

        // And the composition, at the window's minimum.
        let content = DesignTokens.Layout.windowSize.width - 2 * Row.horizontalPadding
        XCTAssertLessThanOrEqual(
            2 * Row.numeralColumnWidth + Row.numeralColonWidth,
            content,
            "`600:00` does not fit the content column at the window's minimum width"
        )
    }
}
