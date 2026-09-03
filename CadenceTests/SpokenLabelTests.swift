import SwiftUI
import XCTest
@testable import Cadence

/// That the four surfaces actually *say* what `SpokenText` prints.
///
/// **Why this suite exists.** `SpokenTextTests` is thorough about the strings and fenced
/// none of the views that use them. Four mutations each left the whole suite green:
/// deleting the window numerals' `SpokenText.clockLabel`, deleting the buffer chips'
/// `SpokenText.buffer`, deleting the dropdown header's `clockLabel`, and reverting the
/// menu-bar item's label to `clockText` — which restores exactly the defect Stage 5 was
/// asked to fix, VoiceOver reading `05:00` as "zero five colon zero zero" instead of
/// "5 minutes". A string helper nothing is proven to call is documentation.
///
/// **How the label is read, and why it is not the accessibility API.** On macOS SwiftUI
/// materialises its `NSAccessibility` tree lazily, and only for a real accessibility
/// client attached to the process: an `NSHostingView` hosted in a test answers
/// `accessibilityChildren()` with an empty array however it is laid out, ordered front, or
/// pumped, and making a client attach means granting the test runner the system
/// Accessibility permission — a machine-wide setting a unit test has no business changing.
/// `ImageRenderer`, which `DropdownGeometryTests` uses for geometry, rasterises pixels and
/// carries no labels at all.
///
/// So the labels are read out of the composed view *value* instead.
/// `.accessibilityLabel("…")` is a modifier, and a modified view is a struct that stores
/// its modifier — so the label is a `String` reachable from `Mirror(reflecting: view.body)`,
/// and a deleted modifier takes it out of the type. That is a dependency on SwiftUI's
/// representation rather than on its behaviour, and it is chosen with the trade named: it
/// is the only mechanism available in-process that a deleted label can fail, and if a
/// future SwiftUI stores labels elsewhere these tests fail loudly with the string missing
/// rather than passing on a view that has stopped saying anything.
///
/// The labels asserted are therefore checked for *presence in the composed row*. Each is a
/// sentence no visible element on the same surface renders — `Time remaining` beside the
/// digits, `End early by 1 minute` beside `1m` — so a match is the label and not the copy.
@MainActor
final class SpokenLabelTests: XCTestCase {
    nonisolated private static let suiteName = "group.com.alexmathews.cadence.tests"

    private var store: SharedStore {
        SharedStore(suiteName: Self.suiteName, reloadsWidgets: false)
    }

    nonisolated override func setUp() {
        super.setUp()
        Self.clearScratchSuite()
    }

    nonisolated override func tearDown() {
        Self.clearScratchSuite()
        super.tearDown()
    }

    nonisolated private static func clearScratchSuite() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let plist = URL.homeDirectory
            .appending(path: "Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    // MARK: - Harvest

    /// Every `String` reachable from a composed view, which is where its accessibility
    /// labels and values live along with its visible copy.
    ///
    /// The depth and node bounds are guards, not tuning: a SwiftUI view graph is a tree of
    /// nested generic structs and an unbounded walk over a `Color` or a `Font` can wander
    /// a long way for nothing. Both are far above what any row here needs — the widest is
    /// under a thousand nodes — and a truncated walk would show up as a missing label,
    /// which is a failure rather than a pass.
    private func labels(of view: some View) -> Set<String> {
        var found: Set<String> = []
        var visited = 0
        harvest(view.body, depth: 0, into: &found, visited: &visited)
        return found
    }

    private func harvest(
        _ value: Any,
        depth: Int,
        into found: inout Set<String>,
        visited: inout Int
    ) {
        guard depth < 32, visited < 100_000 else { return }
        visited += 1

        if let string = value as? String {
            found.insert(string)
            return
        }
        for child in Mirror(reflecting: value).children {
            harvest(child.value, depth: depth + 1, into: &found, visited: &visited)
        }
    }

    private func assertSays(
        _ expected: String,
        _ view: some View,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let found = labels(of: view)
        XCTAssertTrue(
            found.contains(expected),
            "\(message) — expected the label \"\(expected)\"",
            file: file,
            line: line
        )
    }

    /// The harvest has to be capable of *not* finding a label, or every assertion above is
    /// vacuous. Same row, a sentence it does not carry.
    func testTheHarvestFailsWhenALabelIsAbsent() {
        let found = labels(of: MenuBarDropdown.DropdownHeader(
            clockText: "05:00",
            statusWord: "Focus",
            status: .running,
            spokenClock: "5 minutes"
        ))
        XCTAssertTrue(found.contains("Time remaining"), "the label this row does carry")
        XCTAssertFalse(
            found.contains("Session duration"),
            "a running row must not carry idle's label, and the harvest must be able to say so"
        )
        XCTAssertFalse(found.contains("Cadence, ready"))
    }

    // MARK: - The window's numerals

    /// The window's clock is one accessibility element carrying the role, with the time as
    /// its value — the split VoiceOver expects, since the role is read once when focus
    /// lands and the value is re-read as it changes.
    ///
    /// All four statuses, because the label is the only thing that distinguishes `idle`'s
    /// numerals from `complete`'s: both are non-editable and neither is derivable from
    /// `isEditable`.
    func testTheWindowNumeralsAnnounceTheirRoleAndTheTimeInWords() {
        for (status, label) in [
            (SessionStatus.idle, "Session duration"),
            (.running, "Time remaining"),
            (.paused, "Time remaining, paused"),
            (.complete, "Session complete"),
        ] {
            let numerals = EditableNumerals(
                duration: 5 * minute,
                color: DesignTokens.TextColor.primary,
                accessibilityStatus: status,
                isEditable: status == .idle,
                commit: { _ in },
                start: {}
            )
            assertSays(label, numerals, "the window's numerals in \(status)")
        }

        // And the value, in words rather than as the padded glyphs. This is the whole
        // point of `SpokenText.clockLabel` having a companion: `05:00` reads as
        // "zero five colon zero zero".
        assertSays(
            "5 minutes",
            EditableNumerals(
                duration: 5 * minute,
                color: DesignTokens.TextColor.primary,
                accessibilityStatus: .running,
                isEditable: false,
                commit: { _ in },
                start: {}
            ),
            "the window's countdown is announced in words"
        )
    }

    // MARK: - The window's buffer chips

    /// `off`, `1m`, `2m`, `3m` are abbreviations chosen for a 520 pt window; read verbatim
    /// they come out as "two em".
    func testTheBufferChipsSayWhatPressingThemDoes() {
        for (option, label) in [
            (BufferOption.all[0], "Do not end early"),
            (BufferOption.all[1], "End early by 1 minute"),
            (BufferOption.all[2], "End early by 2 minutes"),
            (BufferOption.all[3], "End early by 3 minutes"),
        ] {
            assertSays(
                label,
                BufferChip(option: option, isSelected: false, action: {}),
                "the \(option.label) buffer chip"
            )
        }
    }

    // MARK: - The dropdown's header

    /// One stop, not two: the word beside the clock is the session's *name* while running,
    /// so reading them separately gives a bare padded number and then a bare title.
    func testTheDropdownHeaderAnnouncesTheClockAndTheWordAsOneSentence() {
        for (status, label) in [
            (SessionStatus.idle, "Session duration"),
            (.running, "Time remaining"),
            (.paused, "Time remaining, paused"),
            (.complete, "Session complete"),
        ] {
            let header = MenuBarDropdown.DropdownHeader(
                clockText: "05:00",
                statusWord: "Design review",
                status: status,
                spokenClock: "5 minutes"
            )
            assertSays(label, header, "the dropdown header in \(status)")
        }

        // The value is an interpolated `LocalizedStringKey`, so what survives into the
        // composed view is the format and its two arguments rather than the joined
        // sentence — SwiftUI defers the substitution to the localisation lookup. The
        // format is still the trace of `.accessibilityValue` being applied at all, which
        // is what deleting it would remove.
        assertSays(
            "%@, %@",
            MenuBarDropdown.DropdownHeader(
                clockText: "05:00",
                statusWord: "Design review",
                status: .running,
                spokenClock: "5 minutes"
            ),
            "the header pairs the spoken clock with the word beside it as one value"
        )
    }

    // MARK: - The menu-bar item

    /// The status item is one rasterised image, so it carries the whole sentence — and the
    /// clock in words, which is the defect Stage 5 fixed. Reverting this to `clockText`
    /// gives "Cadence, 05:00 remaining", read aloud as "zero five colon zero zero".
    func testTheMenuBarItemNamesTheAppAndSpeaksTheClockInWords() {
        let now = Date()

        let cases: [(String, SessionState)] = [
            ("Cadence, ready", SessionState.idle()),
            ("Cadence, 5 minutes remaining", SessionState.running(
                plannedDuration: 25 * minute,
                startedAt: now,
                endsAt: now.addingTimeInterval(5 * minute),
                segmentStartedAt: now
            )),
            ("Cadence, paused at 5 minutes", SessionState.paused(
                startedAt: now.addingTimeInterval(-20 * minute),
                remaining: 5 * minute,
                focusedBefore: 20 * minute
            )),
            ("Cadence, session complete", SessionState.complete(
                startedAt: now.addingTimeInterval(-25 * minute),
                completedAt: now,
                focusedBefore: 25 * minute
            )),
        ]

        for (label, state) in cases {
            Self.clearScratchSuite()
            store.save(state)
            let controller = SessionController(store: store, now: now)

            assertSays(label, MenuBarStatusLabel(controller: controller), "the status item")
            XCTAssertFalse(
                labels(of: MenuBarStatusLabel(controller: controller)).contains(controller.clockText),
                """
                the status item is announcing the padded glyphs (\(controller.clockText)) \
                rather than the time in words
                """
            )
        }
    }
}
