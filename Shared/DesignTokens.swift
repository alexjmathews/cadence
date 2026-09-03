import SwiftUI

/// Every value in the visual specification, declared once (D5). Both targets
/// compile this file, which is what keeps the app and the widget extension
/// visually identical; no view body carries a literal color or metric.
///
/// The specification was authored as an HTML export, so its px figures are read
/// as points with no conversion.
enum DesignTokens {

    // MARK: - Color

    enum Surface {
        static let base = Color(hex: 0x0B1024)
        /// The whole shell recolors once a session finishes, title bar included.
        static let complete = Color(hex: 0x04211C)
        /// Dropdown material, with vibrancy behind it.
        static let sheet = Color(.sRGB, red: 32 / 255, green: 32 / 255, blue: 35 / 255, opacity: 0.94)
        /// Chips, secondary buttons, list rows.
        static let fillSubtle = Color(.sRGB, white: 1, opacity: 0.07)
        /// Row and preset hover.
        static let fillHover = Color(hex: 0x2F6BFF, opacity: 0.13)
        /// Dividers and hairline borders.
        static let hairline = Color(.sRGB, white: 1, opacity: 0.12)
        static let progressTrack = Color(.sRGB, white: 1, opacity: 0.10)
        /// The window's calendar-strip footer (§3.1). The specification names the
        /// row's height but not its wash; the `timer-window--*` mockups measure it
        /// at white 4.5% over both shells — lighter than `fillSubtle`, which is a
        /// chip, not a surface.
        static let fillStrip = Color(.sRGB, white: 1, opacity: 0.045)
        /// A selected chip, as the buffer row's active value is drawn. §1.1 gives
        /// accent fills only a 13% hover; the mockups measure the *selected* state at
        /// 30%, which is what separates it from a row the pointer merely rests on.
        static let fillAccentSelected = Color(hex: 0x2F6BFF, opacity: 0.30)
        /// Stroked at `Component.windowRingWidth` around the window, containing it
        /// against a light desktop.
        static let windowRing = Color(.sRGB, white: 0, opacity: 0.30)
        /// The selection drawn behind an editing numeral. Left to itself macOS puts
        /// its system grey there — a solid slab roughly 117 × 108 pt over the white
        /// or mint digits, which appears in no mockup and in nothing §1.1 names. The
        /// accent at the same weight `fillAccentSelected` gives the buffer row's
        /// selected chip is the relationship the window already uses for "selected".
        static let numeralSelection = Color(hex: 0x2F6BFF, opacity: 0.30)
        /// The fill behind the strip's `Timer until 3:30` action and the day list's
        /// `Back to timer`. §1.1 names no fill for either; both measure at white 12%
        /// in the `timer-window--idle-with-event` and `--idle-day-list-expanded`
        /// mockups — heavier than `fillSubtle`, which is what lifts the strip's one
        /// action clear of a footer that is already a wash over the shell.
        static let fillStripAction = Color(.sRGB, white: 1, opacity: 0.12)
    }

    enum Accent {
        /// Primary button, progress fill, running glyph, start actions.
        static let base = Color(hex: 0x2F6BFF)
        /// Accent-colored labels on dark, e.g. "Timer until 3:30".
        static let text = Color(hex: 0x8FB4FF)
        /// Progress fill, glyph and primary button once complete.
        static let complete = Color(hex: 0x2FE0A6)
        /// "Session complete" heading and the complete numerals.
        static let completeText = Color(hex: 0x6FEFC6)
        /// The summary line under that heading. §1.2 gives the complete shell one
        /// text color; the mockup draws the span and focused total at 72% of it, so
        /// the heading still leads. The grey `TextColor` levels would break the mint
        /// wash.
        static let completeCaption = Color(hex: 0x6FEFC6, opacity: 0.72)
        /// Calendar event color bar and event-named sessions.
        static let event = Color(hex: 0xFF8A3D)
        /// The hairline around the strip's `Timer until 3:30`. §1.1 gives hairlines
        /// one white value; the `timer-window--idle-with-event` mockup draws this one
        /// in the accent, which is what marks the strip's single start action out from
        /// the two icon buttons beside it.
        static let stripAction = Color(hex: 0x2F6BFF, opacity: 0.55)

        /// Calendar rows inherit their source calendar's color; these are the ones
        /// the day list is composed against.
        static let calendarColors: [Color] = [
            Color(hex: 0x2F6BFF),
            Color(hex: 0x2FE0A6),
            Color(hex: 0xA184C8),
        ]
    }

    enum TextColor {
        static let primary = Color(hex: 0xF2F2F5)
        static let secondary = Color(labelWhite: 0.58)
        static let tertiary = Color(labelWhite: 0.50)
        static let quaternary = Color(labelWhite: 0.34)
        /// A dismissed row drops its title to this and its color bar to
        /// `dismissedBarOpacity`.
        static let dismissed = Color(labelWhite: 0.42)
        static let onAccent = Color.white
        static let onComplete = Color(hex: 0x04211C)
    }

    static let dismissedBarOpacity: Double = 0.40

    // MARK: - Type

    /// Two families only: UI text is the system face, and anything that counts is
    /// monospaced with tabular figures so digits never shift width. Ships on SF;
    /// `ui-monospace` substitutes for IBM Plex Mono where it cannot be bundled.
    enum Typography {
        static let windowNumeralsSize: CGFloat = 92
        static let windowNumerals = Font.system(
            size: windowNumeralsSize,
            weight: .medium,
            design: .monospaced
        )
        static let windowNumeralsTracking: CGFloat = -6
        /// The numerals' AppKit face. D9's refusal happens at the responder, so the
        /// two editable halves are `NSTextField`s rather than SwiftUI `TextField`s
        /// and need the font in `NSFont` form. `Font.system(design: .monospaced)`
        /// and `NSFont.monospacedSystemFont` resolve to the same face at the same
        /// size and weight, which is what keeps the editable numerals and the
        /// rendered ones the same glyphs. Computed rather than stored because
        /// `NSFont` is not `Sendable`; it is cheap and cached by AppKit.
        static var windowNumeralsNSFont: NSFont {
            NSFont.monospacedSystemFont(ofSize: windowNumeralsSize, weight: .medium)
        }
        static let dropdownNumerals = Font.system(size: 38, weight: .medium, design: .monospaced)
        static let dropdownNumeralsTracking: CGFloat = -1.5
        static let widgetNumerals = Font.system(size: 44, weight: .medium, design: .monospaced)
        static let widgetNumeralsTracking: CGFloat = -2.5

        /// "TODAY · WEDNESDAY" — uppercased by the caller.
        static let sectionLabel = Font.system(size: 11, weight: .semibold)
        static let sectionLabelTracking: CGFloat = 0.5
        /// "IN SESSION", "SESSION COMPLETE" — uppercased by the caller.
        static let widgetPaneLabel = Font.system(size: 10.5, weight: .semibold)
        static let widgetPaneLabelTracking: CGFloat = 0.8

        static let windowButton = Font.system(size: 14, weight: .semibold)
        static let compactButton = Font.system(size: 12.5, weight: .semibold)

        static let windowEventTitle = Font.system(size: 13.5)
        static let stripEventTitle = Font.system(size: 13, weight: .semibold)

        /// Menu rows and day-list titles.
        static let body = Font.system(size: 13)
        /// "running · ends 2:27 PM".
        static let statusLine = Font.system(size: 12.5)
        /// Event meta and the session summary.
        static let caption = Font.system(size: 12)
        /// "end early by", last-synced time.
        static let micro = Font.system(size: 11.5)

        static let listTime = Font.system(size: 12, design: .monospaced)
        /// Preset lengths and buffer chips.
        static let chipMeta = Font.system(size: 11.5, design: .monospaced)
    }

    // MARK: - Sizing

    enum Layout {
        /// The timer window's **default and minimum** size (§3), not its only one:
        /// the window is resizable, and §3.2 says where the extra space goes. This
        /// is the *frame* — what the specification measures and what a screenshot
        /// of the window is.
        static let windowSize = CGSize(width: 520, height: 414)
        /// A standard macOS title bar, which `.windowStyle(.hiddenTitleBar)` makes
        /// transparent but does **not** remove from the frame: the SwiftUI content
        /// view is the frame less this. Asserted against a real `NSWindow` in
        /// `DesignTokensTests`, because a system that measured it differently would
        /// otherwise silently ship a differently sized window.
        static let windowTitlebarHeight: CGFloat = 32
        /// The size the SwiftUI content is laid out to, so that the *frame* is
        /// `windowSize`. Giving SwiftUI 414 shipped a 446 pt window with every row
        /// sitting 32 pt lower against the top edge than the mockup draws it.
        static var windowContentSize: CGSize {
            CGSize(width: windowSize.width, height: windowSize.height - windowTitlebarHeight)
        }
        static let windowRadius: CGFloat = 12
        static let dropdownWidth: CGFloat = 272
        static let dropdownRadius: CGFloat = 12
        static let statusItemHeight: CGFloat = 28
        static let statusItemPillRadius: CGFloat = 5
        static let smallWidgetSize = CGSize(width: 170, height: 170)
        static let mediumWidgetSize = CGSize(width: 364, height: 170)
        static let widgetRadius: CGFloat = 22

        /// The dropdown's vertical rhythm and insets. The specification's row grid
        /// (§3.1) covers the window only, so these are read off the
        /// `menu-bar-dropdown--*` mockups at 2× — the composition reference — and
        /// declared here rather than inlined, per §5.
        enum Dropdown {
            /// Numerals, progress rule, rows and footer share this text column.
            static let horizontalPadding: CGFloat = 16
            /// Buttons and dividers sit 4 pt outside the text column.
            static let controlPadding: CGFloat = 12
            static let topPadding: CGFloat = 14
            /// Holds the 38 pt numerals and the status word on one baseline.
            static let headerHeight: CGFloat = 46
            static let headerToRule: CGFloat = 8
            static let ruleToActions: CGFloat = 10
            static let actionHeight: CGFloat = 30
            static let actionGap: CGFloat = 7
            static let actionsToDivider: CGFloat = 10
            static let rowsTopPadding: CGFloat = 6
            static let rowHeight: CGFloat = 27
            /// Gap after the reserved event-color-bar slot, putting row titles 26 pt
            /// in as the mockups measure them. Duration rows keep the slot so a
            /// meeting row can appear among them without shifting any title
            /// sideways.
            static let rowBarGap: CGFloat = 7
            /// The colour bar in a meeting row, measured off `menu-bar-dropdown--idle`
            /// at 2×. Shorter than the row, so it reads as a mark beside the title
            /// rather than a divider.
            static let rowBarHeight: CGFloat = 13
            static let rowsBottomPadding: CGFloat = 6
            /// `Open Cadence ⌘O`.
            static let footerHeight: CGFloat = 40
        }

        /// The status item's three states. The system owns the item's height (§3 —
        /// 28 pt); `pillHeight` is the countdown chip drawn inside it, which the
        /// mockups measure at 20 and which therefore floats with bar margin rather
        /// than filling the chrome.
        enum StatusItem {
            static let glyphSize: CGFloat = 16
            static let pillHeight: CGFloat = 20
            static let pillHorizontalPadding: CGFloat = 3
            static let pillContentGap: CGFloat = 5
            /// The accent's weight in the chip. The mockups lay it over the menu bar
            /// itself; the built pill lays it over `Surface.base` and ships opaque,
            /// because a non-template bitmap cannot follow a light bar. Same
            /// rendered color on a dark bar, legible on a light one — see
            /// `StatusPill`.
            static let pillTintOpacity: Double = 0.28
        }

        /// Reserved row heights are the whole mechanism behind the clock and
        /// buttons never moving between states: the rows are always allocated and
        /// only their contents change.
        enum WindowRow {
            /// Event-named sessions only; reserved otherwise.
            static let eventTitleHeight: CGFloat = 20
            static let numeralsHeight: CGFloat = 96
            static let numeralsTopInset: CGFloat = 10
            /// Idle: presets and buffer. Running or complete: rule and status line.
            static let swapSlotHeight: CGFloat = 62
            static let swapSlotTopInset: CGFloat = 10
            static let buttonsHeight: CGFloat = 40
            static let buttonsTopInset: CGFloat = 6
            /// Footer; holds its height when empty.
            static let calendarStripHeight: CGFloat = 68

            // The specification's table (§3.1) gives the five row heights. The
            // insets, columns and gaps below place those rows inside the fixed
            // 520 × 414 pt frame and are read off the `timer-window--*` mockups at
            // 2× — the composition reference — rather than inlined, per §5.

            /// The *minimum* space between the window's own top edge and the reserved
            /// event-title row, at the window's default height. The title bar is
            /// transparent, so the shell color reaches the traffic lights and this
            /// inset is what keeps the first row clear of them. It is measured from
            /// the frame, which is what the mockup measures.
            ///
            /// Per §3.2 this is one of the two flexible regions: extra window height
            /// is split between here and `numeralsToSwapSlotInset`, keeping the
            /// numerals block optically centred while every row keeps its height.
            static let topInset: CGFloat = 49
            /// `topInset` as the *content view* sees it. The content view starts a
            /// title bar below the frame's top edge (`windowTitlebarHeight`), so the
            /// grid — which lives inside the content view — lays out the difference
            /// and the row still lands 49 pt below the window's own edge.
            static var contentTopInset: CGFloat {
                topInset - DesignTokens.Layout.windowTitlebarHeight
            }
            /// The other flexible region (§3.2) — zero at the default height, and
            /// half of any extra beyond it.
            static let numeralsToSwapSlotInset: CGFloat = 0
            /// Fixed slack between the button row and the footer. It does *not*
            /// stretch: §3.2 puts the growth around the numerals, so the transport
            /// stays where the eye left it however tall the window gets.
            static let buttonsToStripGap: CGFloat = 53
            /// A caret-visible floor for an emptied numeral field, at roughly one
            /// 92 pt monospaced digit. Without it a cleared field collapses to zero
            /// width and takes the caret with it.
            static let numeralFieldMinimumWidth: CGFloat = 50
            /// The progress rule's column, and the widest any row may run.
            static let horizontalPadding: CGFloat = 40
            /// The event-title row's color bar and the gap to the title.
            static let eventTitleBarHeight: CGFloat = 14
            static let eventTitleBarGap: CGFloat = 8
            /// Between the primary and secondary buttons.
            static let buttonGap: CGFloat = 10
            /// Between quick-duration chips, and from that row to the buffer row.
            static let presetChipGap: CGFloat = 6
            static let presetsToBufferGap: CGFloat = 6
            /// Between the "end early by" label and the buffer chips, and between
            /// the chips themselves.
            static let bufferChipGap: CGFloat = 4
            /// From the progress rule to the line beneath it, in both the running
            /// and the complete slot.
            static let ruleToStatusGap: CGFloat = 11

            /// The strip's own insets. Its 68 pt is fixed from day one, so the
            /// empty state is laid out on the same column the event row will use.
            static let stripHorizontalPadding: CGFloat = 16
            /// From the event color bar's slot to the text beside it.
            static let stripBarGap: CGFloat = 11
            /// The color bar runs the height of the strip's content band, not the
            /// strip.
            static let stripBarHeight: CGFloat = 34
            /// Between the strip's trailing controls.
            static let stripControlGap: CGFloat = 12
            /// The `All events ☰` button's reserved width, and the gap between its
            /// label and its glyph. The button is shipped disabled in stage 2 and
            /// wired up in stage 3; reserving the width now is what keeps that from
            /// shoving the refresh icon 118 pt left and reflowing the strip's
            /// trailing edge.
            static let stripAllEventsWidth: CGFloat = 106
            static let stripAllEventsGap: CGFloat = 7
            /// The strip's event row: the title over its meta line, and the width
            /// reserved for `Timer until 3:30`. The action's width is fixed for the
            /// same reason `stripAllEventsWidth` is — the label's clock changes with
            /// the event, and a button that resized with it would walk the two icon
            /// buttons beside it along the strip.
            static let stripTitleToMetaGap: CGFloat = 2
            static let stripActionWidth: CGFloat = 117
            static let stripActionHeight: CGFloat = 28
        }

        /// The day list drawn over the timer by `☰` (the
        /// `timer-window--idle-day-list-expanded` mockup). The visual specification's
        /// row grid (§3.1) covers the timer's rows only, so these are read off that
        /// mockup at 2× — the composition reference — and declared here per §5.
        ///
        /// It shares the window's 68 pt footer and its 49 pt top inset, which is what
        /// keeps the strip's bar and the list's rows on one column and the footer
        /// exactly where the timer left it.
        enum DayList {
            /// `TODAY · WEDNESDAY` and `synced 2:13 PM`, above the hairline.
            static let headerHeight: CGFloat = 34
            static let headerToRowsGap: CGFloat = 5
            /// One event: 28 pt of colour bar in a 44 pt row, per §4's list row.
            static let rowHeight: CGFloat = 44
            static let rowBarHeight: CGFloat = 28
            /// From the bar to the time, and from the time column to the title.
            static let rowBarGap: CGFloat = 11
            /// A fixed column, so every title starts on the same edge whatever the
            /// hour is.
            static let timeColumnWidth: CGFloat = 62
            static let timeToTitleGap: CGFloat = 12
            /// `Back to timer`, in the footer.
            static let backButtonWidth: CGFloat = 99
            static let backButtonHeight: CGFloat = 27
        }
    }

    // MARK: - Components

    enum Component {
        static let progressRuleHeight: CGFloat = 5
        static let progressRuleRadius: CGFloat = 3
        static let compactProgressRuleHeight: CGFloat = 4
        static let compactProgressRuleRadius: CGFloat = 2

        static let primaryButtonPadding = EdgeInsets(top: 10, leading: 32, bottom: 10, trailing: 32)
        static let primaryButtonRadius: CGFloat = 9
        static let secondaryButtonPadding = EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        static let secondaryButtonRadius: CGFloat = 9
        static let secondaryButtonBorderWidth: CGFloat = 0.5

        static let presetChipPadding = EdgeInsets(top: 7, leading: 13, bottom: 7, trailing: 13)
        static let presetChipRadius: CGFloat = 8
        static let bufferChipPadding = EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
        static let bufferChipRadius: CGFloat = 4

        static let stripIconButtonSize: CGFloat = 28
        static let stripIconButtonRadius: CGFloat = 7
        static let refreshIconButtonSize: CGFloat = 24
        static let refreshIconButtonRadius: CGFloat = 6

        static let eventColorBarWidth: CGFloat = 3
        static let eventColorBarRadius: CGFloat = 2

        static let listRowPadding = EdgeInsets(top: 9, leading: 8, bottom: 9, trailing: 8)
        static let listRowRadius: CGFloat = 8
        static let listRowGap: CGFloat = 6

        static let hairlineWidth: CGFloat = 0.5
        /// Press feedback. The specification does not name it; one value shared by
        /// every control is what keeps buttons and rows feeling like one surface.
        static let pressedOpacity: Double = 0.8
        /// The window's containment ring: a 0.5pt stroke, not a shadow. The spec
        /// writes it as a shadow spread, which SwiftUI has no equivalent for.
        static let windowRingWidth: CGFloat = 0.5
        /// Every widget control is a single App Intent, and none is smaller.
        static let widgetTapTarget: CGFloat = 30
    }

    /// SwiftUI's shadow radius is roughly half a CSS blur, which is the conversion
    /// applied to the specification's values.
    struct Shadow: Equatable, Sendable {
        var color: Color
        var radius: CGFloat
        var x: CGFloat
        var y: CGFloat

        static let window = Shadow(color: .black.opacity(0.40), radius: 30, x: 0, y: 24)
        static let sheet = Shadow(color: .black.opacity(0.44), radius: 17, x: 0, y: 12)
        static let widget = Shadow(color: .black.opacity(0.42), radius: 15, x: 0, y: 10)
    }
}

extension Color {
    /// Hex literals as written in the visual specification.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// The `rgba(235,235,245,…)` label white the text levels are built from.
    fileprivate init(labelWhite opacity: Double) {
        self.init(.sRGB, red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: opacity)
    }
}
