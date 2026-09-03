import AppKit
import SwiftUI
import XCTest
@testable import Cadence

/// Where the widget's ink actually lands, measured off a render of the real views at
/// the real family sizes.
///
/// **Why this suite exists.** Every other widget test asserts what the card *says*;
/// none of them can see where it says it. A layout fault is invisible to them by
/// construction, and one got through: `WidgetTileView`'s medium transport takes its
/// intrinsic width and is allowed to overrun the 151 pt tile column, which makes the
/// enclosing `VStack` report the transport's width rather than the column's. The
/// column's `frame(width:)` was centring that oversize stack, so both complete-state
/// medium cards drew their status dot, their numerals, their progress rule and their
/// primary button 16 pt to the *left* of the card — clipped at the edge — while
/// `WidgetPresentationTests` stayed green.
///
/// So the assertion is a floor on the content's leading edge: nothing may be drawn
/// left of the card's own `padding`, in either family, in any state. That fences the
/// whole class rather than the one instance, which is why it is parameterised over
/// every state the harness renders instead of over the two that were broken.
@MainActor
final class WidgetGeometryTests: XCTestCase {

    // MARK: - Fixtures

    private static let event = EventOccurrence(
        id: "meeting|1",
        title: "Fixture meeting",
        startsAt: Clock.at(15, 30),
        endsAt: Clock.at(16, 30),
        colorHex: "FF8A3D"
    )

    private static let now = Clock.at(14, 12, 28)

    private static var snapshot: CalendarSnapshot {
        CalendarSnapshot(
            day: Clock.startOfDay(now),
            events: [event],
            lastSyncedAt: Clock.at(14, 10),
            access: .authorized
        )
    }

    private static var emptySnapshot: CalendarSnapshot {
        CalendarSnapshot(
            day: Clock.startOfDay(now),
            events: [],
            lastSyncedAt: Clock.at(14, 10),
            access: .authorized
        )
    }

    /// `Start another` is the widest primary label in the product, and it is the label
    /// that overran the column. A title long enough to need truncating rides along, so
    /// the pane's own overflow is in the frame too.
    private static func completeState(title: String?) -> SessionState {
        .complete(
            title: title,
            startedAt: Clock.at(13, 48),
            completedAt: Clock.at(14, 13),
            focusedBefore: 25 * minute
        )
    }

    private static func runningState(title: String?) -> SessionState {
        .running(
            title: title,
            linkedEventKey: title == nil ? nil : "meeting|0",
            startedAt: Clock.at(14, 2),
            endsAt: Clock.at(14, 27),
            segmentStartedAt: Clock.at(14, 2)
        )
    }

    // MARK: - Presentation

    /// `Text(timerInterval:)` counts against the real clock, so in a still render a
    /// 2026 deadline would draw `0:00` and its width would not be the width the live
    /// widget has. Substituting the string the fixture instant implies is the one
    /// change this suite makes to the shipping view — and it substitutes the *widest*
    /// legitimate clock, `600:00` (D10), so the measurement is taken against the worst
    /// case rather than a comfortable one.
    private func tile(
        _ state: SessionState,
        suggestion: EventOccurrence? = nil,
        widestClock: Bool = false
    ) -> WidgetTile {
        var value = WidgetPresentation.tile(
            for: state,
            suggestion: suggestion,
            now: Self.now,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )
        if case .interval = value.countdown {
            value.countdown = .text(widestClock ? "600:00" : ClockFormatter.text(state.remaining(Self.now)))
        } else if widestClock {
            value.countdown = .text("600:00")
        }
        return value
    }

    private func pane(_ state: SessionState, snapshot: CalendarSnapshot?) -> WidgetPane {
        WidgetPresentation.pane(
            for: state,
            snapshot: snapshot,
            dismissed: [],
            preferences: Preferences(),
            now: Self.now,
            calendar: Clock.calendar,
            locale: Clock.locale,
            timeZone: Clock.timeZone
        )
    }

    // MARK: - Rendering

    /// The bounding box, in points, of every pixel the view painted.
    ///
    /// `containerBackground(for: .widget)` is inert outside a WidgetKit host, so the
    /// card renders on transparency and "content" is simply "not transparent". That is
    /// what makes the measurement possible without knowing a single colour, and it is
    /// also why the shell fill is not laid down here: an opaque background would make
    /// the bounding box the frame.
    private func contentBounds(of view: some View, size: CGSize) throws -> CGRect {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "the view produced no render")

        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, 0, "the render is entirely transparent")

        // Back to points, at the scale the render was taken.
        return CGRect(
            x: CGFloat(minX) / renderer.scale,
            y: CGFloat(minY) / renderer.scale,
            width: CGFloat(maxX - minX + 1) / renderer.scale,
            height: CGFloat(maxY - minY + 1) / renderer.scale
        )
    }

    /// Both edges: nothing left of `padding`, and nothing past the card either. The
    /// trailing check is the same fault mirrored, and it costs one line.
    private func assertWithinCard(
        _ bounds: CGRect,
        size: CGSize,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let padding = DesignTokens.Layout.Widget.padding
        XCTAssertGreaterThanOrEqual(
            bounds.minX, padding,
            "\(label): content starts at x \(bounds.minX), left of the card's \(padding) pt padding",
            file: file, line: line
        )
        XCTAssertLessThanOrEqual(
            bounds.maxX, size.width - padding,
            "\(label): content ends at x \(bounds.maxX), past the card's \(size.width - padding) pt inset",
            file: file, line: line
        )
        XCTAssertGreaterThanOrEqual(bounds.minY, padding, "\(label): content above the padding", file: file, line: line)
        XCTAssertLessThanOrEqual(
            bounds.maxY, size.height - padding,
            "\(label): content below the padding", file: file, line: line
        )
    }

    // MARK: - Small

    func testTheSmallCardKeepsEveryStateInsideItsPadding() throws {
        let size = DesignTokens.Layout.smallWidgetSize
        let cases: [(String, WidgetTile)] = [
            ("idle with a suggestion", tile(.idle(), suggestion: Self.event)),
            ("idle with none", tile(.idle())),
            ("running", tile(Self.runningState(title: "Fixture meeting"))),
            ("paused", tile(.paused(
                title: "Fixture meeting",
                startedAt: Clock.at(14, 2),
                remaining: 14 * minute + 32,
                focusedBefore: 10 * minute + 28
            ))),
            ("complete", tile(Self.completeState(title: "Fixture meeting"))),
        ]

        for (label, value) in cases {
            let bounds = try contentBounds(of: SmallWidgetView(tile: value), size: size)
            assertWithinCard(bounds, size: size, "small \(label)")
        }
    }

    // MARK: - Medium

    func testTheMediumCardKeepsEveryStateInsideItsPadding() throws {
        let size = DesignTokens.Layout.mediumWidgetSize
        let cases: [(String, SessionState, EventOccurrence?, CalendarSnapshot?)] = [
            ("idle with suggestions", .idle(), Self.event, Self.snapshot),
            ("idle with an empty calendar", .idle(), nil, Self.emptySnapshot),
            ("running", Self.runningState(title: "A meeting title long enough to truncate"), nil, Self.snapshot),
            ("running with no event", Self.runningState(title: nil), nil, Self.snapshot),
            ("complete", Self.completeState(title: "A meeting title long enough to truncate"), nil, Self.snapshot),
            ("complete with no event", Self.completeState(title: nil), nil, Self.snapshot),
        ]

        for (label, state, suggestion, snapshot) in cases {
            let value = tile(state, suggestion: suggestion)
            let bounds = try contentBounds(
                of: MediumWidgetView(tile: value, pane: pane(state, snapshot: snapshot)),
                size: size
            )
            assertWithinCard(bounds, size: size, "medium \(label)")
        }
    }

    /// The specific regression, asserted specifically as well as generally: the medium
    /// complete card's tile column starts exactly on the padding. `Start another  +5`
    /// is 32 pt wider than the column it sits in, and the whole point of the fix is
    /// that the overrun is anchored trailing rather than split across both edges.
    func testTheCompleteMediumCardStartsItsColumnOnThePadding() throws {
        let size = DesignTokens.Layout.mediumWidgetSize
        for title in ["A meeting title long enough to truncate", nil] {
            let state = Self.completeState(title: title)
            let value = tile(state)
            let bounds = try contentBounds(
                of: MediumWidgetView(tile: value, pane: pane(state, snapshot: Self.snapshot)),
                size: size
            )
            XCTAssertEqual(
                bounds.minX, DesignTokens.Layout.Widget.padding, accuracy: 0.5,
                "the complete card's tile column must start on the padding, not left of it"
            )
        }
    }

    /// D10 at its widest: `600:00` is the longest clock `ClockFormatter` can produce,
    /// and the plan accepts it *scaling* on the widget families precisely because it
    /// must not leave the surface. This is that promise, measured.
    func testTheWidestClockStaysOnBothCards() throws {
        let state = Self.runningState(title: "A meeting title long enough to truncate")

        let small = try contentBounds(
            of: SmallWidgetView(tile: tile(state, widestClock: true)),
            size: DesignTokens.Layout.smallWidgetSize
        )
        assertWithinCard(small, size: DesignTokens.Layout.smallWidgetSize, "small at 600:00")

        let medium = try contentBounds(
            of: MediumWidgetView(
                tile: tile(state, widestClock: true),
                pane: pane(state, snapshot: Self.snapshot)
            ),
            size: DesignTokens.Layout.mediumWidgetSize
        )
        assertWithinCard(medium, size: DesignTokens.Layout.mediumWidgetSize, "medium at 600:00")
    }
}
