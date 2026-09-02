import XCTest
import SwiftUI
@testable import Cadence

/// Four stages consume the token file verbatim, and a mistyped nibble is
/// invisible on screen until someone compares against a mockup. These pin the
/// values the visual specification states.
final class DesignTokensTests: XCTestCase {

    private func components(
        _ color: Color,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        guard let resolved = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("token is not representable in sRGB", file: file, line: line)
            return (0, 0, 0, 0)
        }
        return (
            Double(resolved.redComponent),
            Double(resolved.greenComponent),
            Double(resolved.blueComponent),
            Double(resolved.alphaComponent)
        )
    }

    private func assertColor(
        _ color: Color,
        red: Int,
        green: Int,
        blue: Int,
        alpha: Double = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = components(color, file: file, line: line)
        XCTAssertEqual(actual.red, Double(red) / 255, accuracy: 0.002, "red", file: file, line: line)
        XCTAssertEqual(actual.green, Double(green) / 255, accuracy: 0.002, "green", file: file, line: line)
        XCTAssertEqual(actual.blue, Double(blue) / 255, accuracy: 0.002, "blue", file: file, line: line)
        XCTAssertEqual(actual.alpha, alpha, accuracy: 0.002, "alpha", file: file, line: line)
    }

    // MARK: - Color

    func testSurfaceTokensMatchTheSpecification() {
        assertColor(DesignTokens.Surface.base, red: 0x0B, green: 0x10, blue: 0x24)
        assertColor(DesignTokens.Surface.complete, red: 0x04, green: 0x21, blue: 0x1C)
        assertColor(DesignTokens.Surface.sheet, red: 32, green: 32, blue: 35, alpha: 0.94)
        assertColor(DesignTokens.Surface.fillSubtle, red: 255, green: 255, blue: 255, alpha: 0.07)
        assertColor(DesignTokens.Surface.fillHover, red: 47, green: 107, blue: 255, alpha: 0.13)
        assertColor(DesignTokens.Surface.hairline, red: 255, green: 255, blue: 255, alpha: 0.12)
        assertColor(DesignTokens.Surface.progressTrack, red: 255, green: 255, blue: 255, alpha: 0.10)
        assertColor(DesignTokens.Surface.windowRing, red: 0, green: 0, blue: 0, alpha: 0.30)
    }

    func testAccentTokensMatchTheSpecification() {
        assertColor(DesignTokens.Accent.base, red: 0x2F, green: 0x6B, blue: 0xFF)
        assertColor(DesignTokens.Accent.text, red: 0x8F, green: 0xB4, blue: 0xFF)
        assertColor(DesignTokens.Accent.complete, red: 0x2F, green: 0xE0, blue: 0xA6)
        assertColor(DesignTokens.Accent.completeText, red: 0x6F, green: 0xEF, blue: 0xC6)
        assertColor(DesignTokens.Accent.event, red: 0xFF, green: 0x8A, blue: 0x3D)

        XCTAssertEqual(DesignTokens.Accent.calendarColors.count, 3)
        assertColor(DesignTokens.Accent.calendarColors[0], red: 0x2F, green: 0x6B, blue: 0xFF)
        assertColor(DesignTokens.Accent.calendarColors[1], red: 0x2F, green: 0xE0, blue: 0xA6)
        assertColor(DesignTokens.Accent.calendarColors[2], red: 0xA1, green: 0x84, blue: 0xC8)
    }

    func testTextTokensMatchTheSpecification() {
        assertColor(DesignTokens.TextColor.primary, red: 0xF2, green: 0xF2, blue: 0xF5)
        assertColor(DesignTokens.TextColor.secondary, red: 235, green: 235, blue: 245, alpha: 0.58)
        assertColor(DesignTokens.TextColor.tertiary, red: 235, green: 235, blue: 245, alpha: 0.50)
        assertColor(DesignTokens.TextColor.quaternary, red: 235, green: 235, blue: 245, alpha: 0.34)
        assertColor(DesignTokens.TextColor.dismissed, red: 235, green: 235, blue: 245, alpha: 0.42)
        assertColor(DesignTokens.TextColor.onComplete, red: 0x04, green: 0x21, blue: 0x1C)
        XCTAssertEqual(DesignTokens.dismissedBarOpacity, 0.40)
    }

    // MARK: - Sizing

    func testSurfaceSizesAndRadiiMatchTheSpecification() {
        XCTAssertEqual(DesignTokens.Layout.windowSize, CGSize(width: 520, height: 414))
        XCTAssertEqual(DesignTokens.Layout.windowRadius, 12)
        XCTAssertEqual(DesignTokens.Layout.dropdownWidth, 272)
        XCTAssertEqual(DesignTokens.Layout.dropdownRadius, 12)
        XCTAssertEqual(DesignTokens.Layout.statusItemHeight, 28)
        XCTAssertEqual(DesignTokens.Layout.statusItemPillRadius, 5)
        XCTAssertEqual(DesignTokens.Layout.smallWidgetSize, CGSize(width: 170, height: 170))
        XCTAssertEqual(DesignTokens.Layout.mediumWidgetSize, CGSize(width: 364, height: 170))
        XCTAssertEqual(DesignTokens.Layout.widgetRadius, 22)
    }

    func testWindowRowGridMatchesTheSpecification() {
        typealias Row = DesignTokens.Layout.WindowRow

        XCTAssertEqual(Row.eventTitleHeight, 20)
        XCTAssertEqual(Row.numeralsHeight, 96)
        XCTAssertEqual(Row.numeralsTopInset, 10)
        XCTAssertEqual(Row.swapSlotHeight, 62)
        XCTAssertEqual(Row.swapSlotTopInset, 10)
        XCTAssertEqual(Row.buttonsHeight, 40)
        XCTAssertEqual(Row.buttonsTopInset, 6)
        XCTAssertEqual(Row.calendarStripHeight, 68)

        let rows = Row.eventTitleHeight
            + Row.numeralsTopInset + Row.numeralsHeight
            + Row.swapSlotTopInset + Row.swapSlotHeight
            + Row.buttonsTopInset + Row.buttonsHeight
            + Row.calendarStripHeight
        XCTAssertLessThan(rows, DesignTokens.Layout.windowSize.height, "the grid must fit the fixed window")
    }

    // MARK: - Components

    func testComponentMetricsMatchTheSpecification() {
        typealias Component = DesignTokens.Component

        XCTAssertEqual(Component.progressRuleHeight, 5)
        XCTAssertEqual(Component.progressRuleRadius, 3)
        XCTAssertEqual(Component.compactProgressRuleHeight, 4)
        XCTAssertEqual(Component.compactProgressRuleRadius, 2)

        XCTAssertEqual(Component.primaryButtonPadding, EdgeInsets(top: 10, leading: 32, bottom: 10, trailing: 32))
        XCTAssertEqual(Component.primaryButtonRadius, 9)
        XCTAssertEqual(Component.secondaryButtonPadding, EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18))
        XCTAssertEqual(Component.secondaryButtonRadius, 9)
        XCTAssertEqual(Component.secondaryButtonBorderWidth, 0.5)

        XCTAssertEqual(Component.presetChipPadding, EdgeInsets(top: 7, leading: 13, bottom: 7, trailing: 13))
        XCTAssertEqual(Component.presetChipRadius, 8)
        XCTAssertEqual(Component.bufferChipPadding, EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
        XCTAssertEqual(Component.bufferChipRadius, 4)

        // "6–7px" is 7 for the 28pt strip button and 6 for the 24pt refresh button.
        XCTAssertEqual(Component.stripIconButtonSize, 28)
        XCTAssertEqual(Component.stripIconButtonRadius, 7)
        XCTAssertEqual(Component.refreshIconButtonSize, 24)
        XCTAssertEqual(Component.refreshIconButtonRadius, 6)

        XCTAssertEqual(Component.eventColorBarWidth, 3)
        XCTAssertEqual(Component.eventColorBarRadius, 2)
        XCTAssertEqual(Component.listRowPadding, EdgeInsets(top: 9, leading: 8, bottom: 9, trailing: 8))
        XCTAssertEqual(Component.listRowRadius, 8)
        XCTAssertEqual(Component.listRowGap, 6)

        XCTAssertEqual(Component.hairlineWidth, 0.5)
        XCTAssertEqual(Component.windowRingWidth, 0.5, "the spec's 0.5px ring is a stroke, not a shadow")
        XCTAssertEqual(Component.widgetTapTarget, 30)
    }

    func testShadowsHalveTheSpecifiedBlur() {
        XCTAssertEqual(DesignTokens.Shadow.window.radius, 30)
        XCTAssertEqual(DesignTokens.Shadow.window.y, 24)
        XCTAssertEqual(DesignTokens.Shadow.sheet.radius, 17)
        XCTAssertEqual(DesignTokens.Shadow.sheet.y, 12)
        XCTAssertEqual(DesignTokens.Shadow.widget.radius, 15)
        XCTAssertEqual(DesignTokens.Shadow.widget.y, 10)
    }

    // MARK: - Type

    func testNumeralTrackingMatchesTheSpecification() {
        XCTAssertEqual(DesignTokens.Typography.windowNumeralsTracking, -6)
        XCTAssertEqual(DesignTokens.Typography.dropdownNumeralsTracking, -1.5)
        XCTAssertEqual(DesignTokens.Typography.widgetNumeralsTracking, -2.5)
        XCTAssertEqual(DesignTokens.Typography.sectionLabelTracking, 0.5)
        XCTAssertEqual(DesignTokens.Typography.widgetPaneLabelTracking, 0.8)
    }
}
