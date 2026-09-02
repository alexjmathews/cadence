import AppKit
import SwiftUI

/// One half of the window's 92 pt numerals: an `NSTextField` that refuses anything
/// which is not a digit **at the responder** (D9).
///
/// It is AppKit rather than a SwiftUI `TextField` for one reason. Refusal has to
/// happen where the text is actually being edited. A `Binding` setter that declines
/// to write does not revert an `NSTextField` — the field keeps its own live editing
/// text, so `abc-.:x` stays on screen while the committed plan silently diverges
/// from it.
///
/// The place that can say *no* and have the field mean it is a `Formatter`'s
/// `isPartialStringValid`, which the field editor consults before adopting any
/// proposed value — so typing, paste and IME commits are all covered by the one rule.
/// (`NSControlTextEditingDelegate` has no `shouldChangeTextIn` hook: writing one
/// compiles, because it is just a method, and is never called.)
///
/// Two other things live here because they are responder-level facts:
///
/// - **Focus is never taken, only given.** The field records whether its caret was
///   *asked for* — by a click, a `Tab` from the other half, or assistive technology —
///   and `WindowChrome` clears one that was not, so a freshly opened window is not a
///   live text field eating keystrokes into the duration.
/// - **Commit is on blur or `Return`**, never per keystroke (D9). `controlTextDidChange`
///   only mirrors the live text back so the other half can be composed against it;
///   the plan moves when the edit is finished.
struct NumeralField: NSViewRepresentable {
    @Binding var text: String
    let field: DurationInput.Field
    let alignment: NSTextAlignment
    let color: Color
    /// Whether this half is the one the shared focus request names. Driving focus
    /// from state the view already re-renders on keeps AppKit and SwiftUI agreeing
    /// about which field has the caret.
    let isFocused: Bool
    /// Called when this field takes the caret, so the shared request can follow a
    /// click the way it follows a `Tab`.
    let onFocus: () -> Void
    /// `Tab` and `Shift-Tab` are the same swap between two fields.
    let onTab: () -> Void
    let onCommit: () -> Void
    let onReturn: () -> Void

    func makeNSView(context: Context) -> NumeralTextField {
        Self.makeField(field: field, delegate: context.coordinator)
    }

    /// The field's construction, factored out so the tests can exercise the shipped
    /// wiring — delegate included — rather than a lookalike assembled beside it.
    @MainActor
    static func makeField(
        field: DurationInput.Field,
        delegate: any NSTextFieldDelegate
    ) -> NumeralTextField {
        let view = NumeralTextField(frame: .zero)
        view.cell = NumeralCell()
        view.delegate = delegate
        view.isEditable = true
        view.isSelectable = true
        view.isBordered = false
        view.isBezeled = false
        view.drawsBackground = false
        view.focusRingType = .none
        view.usesSingleLineMode = true
        view.lineBreakMode = .byClipping
        view.cell?.wraps = false
        view.cell?.isScrollable = true
        view.allowsDefaultTighteningForTruncation = false
        // **The refusal (D9).** Consulted before the field editor adopts anything.
        view.formatter = NumeralFormatter(field: field)
        // The cell centres its line using its *own* font, so leaving it at the system
        // 13 pt while the attributed string is 92 pt drew the digits 60 pt above the
        // field.
        view.font = DesignTokens.Typography.windowNumeralsNSFont
        return view
    }

    func updateNSView(_ view: NumeralTextField, context: Context) {
        context.coordinator.parent = self

        let attributes = attributes()
        if let cell = view.cell as? NumeralCell {
            cell.editingAttributes = attributes
            cell.selectionAttributes = [
                .backgroundColor: NSColor(DesignTokens.Surface.numeralSelection),
                .foregroundColor: NSColor(color),
            ]
            cell.caretColor = NSColor(color)
        }
        view.font = DesignTokens.Typography.windowNumeralsNSFont
        view.alignment = alignment
        // While the field editor holds the text the two already agree, so this only
        // fires when the *plan* changed underneath the field — a preset chip, a
        // widget-driven reset, the window opening — and never fights the caret.
        if view.stringValue != text {
            view.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
        } else if view.currentEditor() == nil {
            view.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
        }

        guard let window = view.window else { return }
        if isFocused, window.firstResponder !== view.currentEditor() {
            view.noteUserFocus()
            window.makeFirstResponder(view)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NumeralTextField,
        context: Context
    ) -> CGSize? {
        // Fills the column it is given so the field's own alignment does the
        // positioning (§3.2's symmetric halves), and takes the font's line height so
        // the digits sit on the same baseline as the SwiftUI colon between them — a
        // fitting size would let the field grow past it and drag the digits off the
        // row.
        CGSize(
            width: proposal.width ?? nsView.fittingSize.width,
            height: NSLayoutManager().defaultLineHeight(
                for: DesignTokens.Typography.windowNumeralsNSFont
            )
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func attributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        return [
            .font: DesignTokens.Typography.windowNumeralsNSFont,
            .kern: DesignTokens.Typography.windowNumeralsTracking,
            .foregroundColor: NSColor(color),
            .paragraphStyle: paragraph,
        ]
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumeralField

        init(parent: NumeralField) {
            self.parent = parent
        }

        /// Mirrors the accepted text back into SwiftUI. Deliberately *not* a commit:
        /// the plan moves on blur or `Return`, so typing `250` walks the plan through
        /// nothing on its way (D9).
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            (notification.object as? NumeralTextField)?.noteUserFocus()
            parent.onFocus()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            (notification.object as? NumeralTextField)?.noteEditingEnded()
            parent.onCommit()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                // Two fields make a cycle, so both directions are the same swap.
                // Handling it here rather than leaning on the key view loop is what
                // keeps `Tab` from wandering off into the preset chips.
                parent.onTab()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommit()
                parent.onReturn()
                return true
            default:
                return false
            }
        }
    }
}

/// The field itself.
final class NumeralTextField: NSTextField {
    /// Whether the caret in this field was *asked for* — by a click, by `Tab` from the
    /// other half, or by assistive technology. SwiftUI installs the first text field
    /// in a window as first responder when the window opens, which is how an untouched
    /// window came to be a live text field eating keystrokes into the duration;
    /// `WindowChrome` clears a caret nobody asked for and leaves this one alone.
    ///
    /// The field stays fully focusable either way: gating `acceptsFirstResponder`
    /// would also put it outside the key view loop and out of VoiceOver's reach, which
    /// is a worse bug than the one being fixed.
    private(set) var isUserFocused = false

    /// The window is movable by its background (the numerals sit on it), and a view
    /// with no background of its own counts as that background as far as AppKit is
    /// concerned — so a click here would start a window drag instead of arriving as
    /// `mouseDown`.
    override var mouseDownCanMoveWindow: Bool { false }

    func noteUserFocus() {
        isUserFocused = true
    }

    func noteEditingEnded() {
        isUserFocused = false
    }

    override func mouseDown(with event: NSEvent) {
        noteUserFocus()
        super.mouseDown(with: event)
    }

    override func setAccessibilityFocused(_ accessibilityFocused: Bool) {
        if accessibilityFocused { noteUserFocus() }
        super.setAccessibilityFocused(accessibilityFocused)
    }
}

/// Carries the numerals' type and the editing treatment into the field editor.
///
/// A field editor is shared window-wide and starts from the system's own
/// attributes, so without this the 92 pt monospaced digits would revert to 13 pt
/// system text the moment the field was clicked, and the selection would be drawn in
/// the system's grey.
final class NumeralCell: NSTextFieldCell {
    var editingAttributes: [NSAttributedString.Key: Any] = [:]
    var selectionAttributes: [NSAttributedString.Key: Any] = [:]
    var caretColor: NSColor = .white

    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        guard let textView = editor as? NSTextView else { return editor }
        textView.typingAttributes = editingAttributes
        textView.selectedTextAttributes = selectionAttributes
        textView.insertionPointColor = caretColor
        textView.defaultParagraphStyle = editingAttributes[.paragraphStyle] as? NSParagraphStyle
        textView.drawsBackground = false
        return editor
    }
}

/// The rule of D9, in the form the field editor asks it.
///
/// `isPartialStringValid` is consulted before *any* proposed value is adopted —
/// keystroke, paste, or IME commit — and answering `false` leaves the field holding
/// exactly what it had. That is what "refused at input rather than validated
/// afterwards" means in AppKit; there is no malformed entry to reject later.
final class NumeralFormatter: Formatter {
    private let field: DurationInput.Field

    init(field: DurationInput.Field) {
        self.field = field
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func string(for obj: Any?) -> String? { obj as? String }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(
        _ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
        proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
        originalString origString: String,
        originalSelectedRange origSelRange: NSRange,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        DurationInput.accepting(partialStringPtr.pointee as String, field) != nil
    }
}
