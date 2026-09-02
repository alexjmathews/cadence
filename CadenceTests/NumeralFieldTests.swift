import AppKit
import SwiftUI
import XCTest
@testable import Cadence

/// The window's numeral fields as they actually behave, not as their rule reads.
///
/// `ClockFormatterTests` already pins `DurationInput`'s rule, and it passed while the
/// shipped field cheerfully accepted `abc-.:x`: the refusal lived in a SwiftUI
/// `Binding` setter that declined to write, which does not revert an `NSTextField`.
/// So these drive the real field editor through the real formatter and coordinator —
/// the same construction `NumeralField.makeNSView` uses — and assert on what the field
/// is left holding.
@MainActor
final class NumeralFieldTests: XCTestCase {

    /// What the shipped view's callbacks would have done, recorded instead.
    @MainActor
    private final class Recorder {
        var text = ""
        var commits = 0
        var tabs = 0
        var returns = 0
        var focuses = 0
    }

    /// A field wired to the shipped coordinator, live in a window so it has a field
    /// editor to type into.
    @MainActor
    private final class Harness {
        let window: NSWindow
        let field: NumeralTextField
        let coordinator: NumeralField.Coordinator
        let recorder = Recorder()

        var text: String { recorder.text }
        var commits: Int { recorder.commits }
        var tabs: Int { recorder.tabs }
        var returns: Int { recorder.returns }

        init(field kind: DurationInput.Field, seed: String, alignment: NSTextAlignment = .right) {
            window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled, .resizable],
                backing: .buffered,
                defer: false
            )
            let recorder = recorder
            recorder.text = seed

            let representable = NumeralField(
                text: Binding(get: { recorder.text }, set: { recorder.text = $0 }),
                field: kind,
                alignment: alignment,
                color: DesignTokens.TextColor.primary,
                isFocused: false,
                onFocus: { recorder.focuses += 1 },
                onTab: { recorder.tabs += 1 },
                onCommit: { recorder.commits += 1 },
                onReturn: { recorder.returns += 1 }
            )
            coordinator = representable.makeCoordinator()
            field = NumeralField.makeField(field: kind, delegate: coordinator)
            window.contentView?.addSubview(field)
            field.frame = CGRect(x: 0, y: 0, width: 400, height: 120)
            field.stringValue = seed
        }

        /// Puts the caret in the field the way a click does, and hands back the field
        /// editor every route into the field goes through.
        func beginEditing() -> NSTextView {
            field.noteUserFocus()
            window.makeFirstResponder(field)
            return field.currentEditor() as! NSTextView
        }

        func blur() {
            window.makeFirstResponder(nil)
        }

        func send(_ selector: Selector, _ editor: NSTextView) {
            _ = coordinator.control(field, textView: editor, doCommandBy: selector)
        }
    }

    /// Types a string one character at a time, as a keyboard does, through the path
    /// that consults the formatter.
    private func type(_ string: String, into editor: NSTextView) {
        for character in string {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
    }

    // MARK: - Refusal reaches the field (D9)

    /// The measured failure: typing this into minutes left `abc-.:x` on screen,
    /// because the refusal lived in a `Binding` setter that could decline to write but
    /// could not make the field forget.
    func testALetterNeverBecomesTheFieldsValue() {
        let harness = Harness(field: .minutes, seed: "25")
        let editor = harness.beginEditing()
        editor.selectedRange = NSRange(location: 0, length: 2)

        type("abc-.:x", into: editor)

        XCTAssertEqual(editor.string, "25", "every one of them was refused")
        XCTAssertEqual(harness.field.stringValue, "25")
    }

    /// And an emptied field takes no more of them than a full one does.
    func testALetterIsRefusedIntoAnEmptyFieldToo() {
        let harness = Harness(field: .minutes, seed: "")
        let editor = harness.beginEditing()

        type("abc-.:x", into: editor)

        XCTAssertEqual(editor.string, "")
    }

    /// The measured failure: `751234` stayed in the field and drew `751234:00` in
    /// 92 pt numerals across both window edges.
    func testAnOverLongEntryStopsAtTheFieldsWidth() {
        let harness = Harness(field: .minutes, seed: "")
        let editor = harness.beginEditing()

        type("751234", into: editor)

        XCTAssertEqual(editor.string, "751", "three digits of minutes, and no more")
    }

    /// The `0…59` clamp is the same refusal, so `999` into seconds must not stick.
    func testASecondsEntryPastFiftyNineIsRefusedByTheField() {
        let harness = Harness(field: .seconds, seed: "", alignment: .left)
        let editor = harness.beginEditing()

        type("999", into: editor)

        XCTAssertEqual(editor.string, "9")
    }

    /// Paste arrives as one replacement over a range rather than as keystrokes, which
    /// is why the refusal lives where it does.
    func testAPastedNonDigitIsRefusedWhole() {
        let harness = Harness(field: .minutes, seed: "25")
        let editor = harness.beginEditing()
        editor.selectedRange = NSRange(location: 0, length: 2)

        editor.insertText("9a9", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.string, "25", "the field keeps what it had")
    }

    func testAPastedDigitStringIsAccepted() {
        let harness = Harness(field: .minutes, seed: "25")
        let editor = harness.beginEditing()
        editor.selectedRange = NSRange(location: 0, length: 2)

        editor.insertText("90", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.string, "90")
    }

    // MARK: - Commit on blur or Return (D9)

    /// Committing per keystroke walked `plannedDuration` through every intermediate
    /// value — two App Group writes and two widget-timeline reloads per character.
    func testTypingCommitsNothing() {
        let harness = Harness(field: .minutes, seed: "")
        let editor = harness.beginEditing()

        type("250", into: editor)

        XCTAssertEqual(editor.string, "250")
        XCTAssertEqual(harness.text, "250", "the live text is mirrored back")
        XCTAssertEqual(harness.commits, 0, "and nothing was committed on the way")
    }

    func testBlurCommitsOnce() {
        let harness = Harness(field: .minutes, seed: "")
        let editor = harness.beginEditing()
        type("50", into: editor)
        XCTAssertEqual(harness.commits, 0)

        harness.blur()

        XCTAssertEqual(harness.commits, 1)
    }

    func testReturnCommitsAndStarts() {
        let harness = Harness(field: .minutes, seed: "")
        let editor = harness.beginEditing()
        type("50", into: editor)

        harness.send(#selector(NSResponder.insertNewline(_:)), editor)

        XCTAssertEqual(harness.commits, 1)
        XCTAssertEqual(harness.returns, 1, "`Return` starts the session from either field")
    }

    /// Both directions of the swap are handled here rather than by the key view loop,
    /// which is what keeps `Tab` from wandering off into the preset chips.
    func testTabAndShiftTabBothSwapTheHalvesAndCommit() {
        let harness = Harness(field: .minutes, seed: "25")
        let editor = harness.beginEditing()

        harness.send(#selector(NSResponder.insertTab(_:)), editor)
        harness.send(#selector(NSResponder.insertBacktab(_:)), editor)

        XCTAssertEqual(harness.tabs, 2)
    }

    /// A caret nobody asked for is what `WindowChrome` clears, so the field has to be
    /// able to say which kind it has. It stays fully focusable either way — refusing
    /// first responder outright would also put it outside the key view loop and out of
    /// VoiceOver's reach.
    func testTheFieldDistinguishesACaretItWasGivenFromOneItWasHanded() {
        let harness = Harness(field: .minutes, seed: "25")

        XCTAssertFalse(
            harness.field.isUserFocused,
            "an opened window's caret was not asked for"
        )

        // SwiftUI's own installation at window-open looks exactly like this, and must
        // not count as intent.
        harness.window.makeFirstResponder(harness.field)
        XCTAssertNotNil(harness.field.currentEditor(), "the field is still focusable")

        harness.blur()
        harness.field.noteUserFocus()
        harness.window.makeFirstResponder(harness.field)
        XCTAssertTrue(harness.field.isUserFocused)

        // And the flag does not survive the edit, so the next window opening cannot
        // inherit intent from the last one.
        harness.blur()
        XCTAssertFalse(harness.field.isUserFocused)
    }

    /// Assistive technology asking for the caret is intent too.
    func testAccessibilityFocusCountsAsIntent() {
        let harness = Harness(field: .minutes, seed: "25")

        harness.field.setAccessibilityFocused(true)

        XCTAssertTrue(harness.field.isUserFocused)
    }

    // MARK: - The commit rule itself

    /// An empty field is a field mid-retype, not an edit that finished. Committing it
    /// would put a nine-second plan in the App Group on the way to a new one.
    func testAnEmptyFieldCommitsNothing() {
        XCTAssertNil(DurationInput.commitDuration(minutes: "", seconds: "00"))
        XCTAssertNil(DurationInput.commitDuration(minutes: "25", seconds: ""))
        XCTAssertNil(DurationInput.commitDuration(minutes: "", seconds: ""))
    }

    /// Nor does a pair that composes to zero, for the same reason
    /// `SessionTransitions.selectDuration` refuses it.
    func testAZeroPairCommitsNothing() {
        XCTAssertNil(DurationInput.commitDuration(minutes: "00", seconds: "00"))
        XCTAssertNil(DurationInput.commitDuration(minutes: "0", seconds: "0"))
    }

    func testAFinishedEditCommitsWhatTheTwoHalvesSay() {
        XCTAssertEqual(DurationInput.commitDuration(minutes: "50", seconds: "00"), 50 * minute)
        XCTAssertEqual(DurationInput.commitDuration(minutes: "00", seconds: "30"), 30)
        XCTAssertEqual(
            DurationInput.commitDuration(minutes: "999", seconds: "59"),
            ClockFormatter.maximumDuration
        )
    }

}
