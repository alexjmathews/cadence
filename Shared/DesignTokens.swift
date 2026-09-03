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
        /// The widget transport's secondary control — `↺`, `+5`. §1.1 gives
        /// secondary buttons `fillSubtle`; at 44 pt over a card that is already dark
        /// that reads as an absence rather than a control, and the
        /// `widget-small--running` and `--complete` mockups measure it at white 12%,
        /// the same weight the strip's action carries for the same reason.
        static let fillWidgetSecondary = Color(.sRGB, white: 1, opacity: 0.12)
        /// The widget transport's primary control **in vibrant rendering mode**, where
        /// the accent fill it normally carries is not available.
        ///
        /// macOS renders desktop widgets by flattening them to a wallpaper-keyed
        /// material, mapping content by *luminance* and discarding hue. `Accent.base`
        /// under `TextColor.onAccent` has ample colour contrast and almost none of the
        /// luminance separation that survives the flattening, so the primary button
        /// renders as a blank slab with its own label invisible inside it. Neutral
        /// translucent white is what the material is built to carry: it flattens to a
        /// lighter panel, and a full-opacity label stays legible on it.
        ///
        /// Heavier than `fillWidgetSecondary` so the transport keeps its hierarchy
        /// once both controls are neutral and colour can no longer distinguish them.
        static let fillVibrantPrimary = Color(.sRGB, white: 1, opacity: 0.26)
        /// The medium's context pane and its suggestion rows over the mint shell.
        /// §1.1 names one `Fill / subtle` for both shells; the `widget-medium--complete`
        /// mockups tint the complete pane with the completion accent rather than
        /// white, which is what keeps it from reading as a grey patch on a green
        /// card.
        static let fillComplete = Color(hex: 0x2FE0A6, opacity: 0.12)
        /// The same pane's border, on the same argument as `fillComplete`.
        static let hairlineComplete = Color(hex: 0x2FE0A6, opacity: 0.28)
        /// The reserved colour bar in a widget suggestion row that has no calendar
        /// colour to inherit — a duration or a clock target. Dimmer than any
        /// `TextColor` level, because it is a mark holding a column open rather than
        /// a thing to read.
        static let widgetRowBar = Color(.sRGB, red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.25)
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
        /// How far the widget's clock may shrink, and the one place in the product where a
        /// clock scales at all.
        ///
        /// D10 forbids compressing, ellipsing or truncating the clock and says the two
        /// menu-bar surfaces widen instead — but 170 × 170 and 364 × 170 are fixed by
        /// WidgetKit, so the widget cannot. Scaling is the remaining option and it is the
        /// acceptable one, because the whole clock stays on screen and legible; an ellipsis
        /// destroys the reading. `Clock.widest` at 44 pt is 148 pt against a 151 pt tile
        /// column, so in practice the scale is headroom rather than a thing that happens.
        static let widgetNumeralsMinimumScale: CGFloat = 0.6

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

    /// The colour bar beside an event, wherever an event appears — the dropdown's meeting
    /// row, the window's strip, the day list, the medium widget's suggestion row.
    ///
    /// Here, and shared, because it is a *derivation* with a fallback and the fallback is
    /// where the four surfaces drifted: the app fell back to `Accent.event` for a calendar
    /// that reported no colour while the widget fell back to its neutral row mark, so one
    /// meeting drew an orange bar in the dropdown and a grey one on the card at the same
    /// moment. One function is the only thing that fixes that class of fault rather than
    /// this instance of it.
    ///
    /// `nil` is *no calendar to inherit from* — a duration row or a clock target — and is
    /// the caller's to handle, because "keep the slot in a neutral mark" is a fact about
    /// the row's grid rather than about the event.
    static func eventBarColor(forHex hex: String?) -> Color {
        hex.flatMap(Color.init(hexString:)) ?? Accent.event
    }

    // MARK: - Clock

    /// The clock is never compressed, ellipsed, or truncated; everything else yields
    /// to it (D10). These are the two values that rule needs in code.
    enum Clock {
        /// The widest legitimate clock, as a string every surface can measure itself
        /// against. `ClockFormatter` carries minutes past 59 rather than rolling over
        /// to hours, so the widest form is three minute digits plus two seconds.
        ///
        /// `999:59` is the largest value `ClockFormatter` will print, but the numerals
        /// are monospaced with tabular figures — every digit has the same advance — so
        /// any six-glyph clock measures identically and `600:00` is the one D10 names.
        static let widest = "600:00"

        /// The clock's layout priority where it shares a row with a label — the
        /// dropdown's status word, and any surface that grows one later. A `Text` at
        /// the default priority beside another flexible `Text` gets *negotiated* with,
        /// which is how a long meeting title came to render the clock as `60:...`.
        ///
        /// The clock also takes its ideal width unconditionally (`.fixedSize`). The two
        /// are belt-and-braces rather than two halves of one mechanism: at the widths
        /// Cadence draws today either one alone is sufficient — removing `.fixedSize`
        /// and keeping this priority still renders the whole clock, and
        /// `DropdownGeometryTests` only fails when *both* are dropped. They are kept
        /// together because they forbid the compression in different ways: a priority
        /// orders it, and `.fixedSize` refuses it, so a wider clock or a narrower sheet
        /// is caught by the second when it outgrows the first.
        static let layoutPriority: Double = 1
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
            /// One footer row — `Open Cadence ⌘O`, `Settings… ⌘,`, `Quit Cadence ⌘Q`.
            /// The sheet carries three of them (D8 as amended in Stage 5), which is
            /// two rows past the mockup's height; `DesignTokensTests` composes the
            /// total and pins it.
            static let footerHeight: CGFloat = 40

            /// The column the numerals hold in the header, at `Clock.widest` in the
            /// dropdown face — 38 pt monospaced, `-1.5` tracking. Measured at
            /// 131.94 pt and rounded up; `DesignTokensTests` re-measures the real face
            /// against this, so a system whose monospaced digits are wider fails the
            /// suite rather than shipping a clipped clock.
            static let clockReservedWidth: CGFloat = 132
            /// The column left for the word beside the numerals. `complete` is the
            /// widest of the four bare status words at 56.36 pt, so reserving this
            /// much is what makes *titles* the only thing that ever truncates (D10) —
            /// the status words themselves always render whole.
            static let statusWordMinimumWidth: CGFloat = 57
            /// The narrowest sheet that can hold the widest clock beside an untruncated
            /// status word. `dropdownWidth` is asserted against this rather than
            /// derived from it: §3 states the sheet's width, and this is the floor that
            /// statement has to clear.
            static var minimumWidth: CGFloat {
                2 * horizontalPadding + clockReservedWidth + controlPadding
                    + statusWordMinimumWidth
            }
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
            /// The column the countdown holds in the pill, at `Clock.widest` in the
            /// pill's face — 12 pt monospaced, no tracking. Measured at 44.51 pt and
            /// rounded up.
            ///
            /// The pill is *reserved* to this width rather than hugging its digits, so
            /// the item does not walk along the menu bar as a session crosses from
            /// `100:00` to `99:59` and the two icons to its left shuffle sideways.
            /// Tabular figures keep `00:00` from moving inside it; three-digit minutes
            /// are what would otherwise move the pill itself.
            static let pillClockWidth: CGFloat = 45
            /// The whole pill at that reservation: the mark, the gap, the clock column
            /// and the chip's own padding. Asserted against a real render in
            /// `WidgetGeometryTests`, which is the only check that the clock is inside
            /// the chip rather than merely narrower than it.
            static var pillWidth: CGFloat {
                2 * pillHorizontalPadding + glyphSize + pillContentGap + pillClockWidth
            }
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
            /// One symmetric numeral column at three digits, in the window face —
            /// 92 pt monospaced, `-6` tracking. `600` measures 152.61 pt; the column
            /// negates the trailing tracking, so its advance is 146.61 — but the
            /// *ink* a render puts down is 147.5, because the glyphs overshoot their
            /// advance and are antialiased at the edges. The reserved column is the one
            /// a render measures, not the one the metrics predict, since the render is
            /// what the user sees.
            ///
            /// §3.2 makes the two halves equal-width columns either side of a colon on
            /// the centre line, so the widest clock the window can draw is twice this
            /// plus the colon's own advance — which has to fit inside the content
            /// column at the window's *minimum* width, or a three-digit session would
            /// push its own numerals under the window edge. `DesignTokensTests` does
            /// that arithmetic.
            static let numeralColumnWidth: CGFloat = 148
            /// The colon's advance at the same face, measured at 50.87 pt. It carries
            /// no tracking — its ink is centred in its own advance, which is what puts
            /// it on the window's centre line.
            static let numeralColonWidth: CGFloat = 51
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

        /// The widget families' internal grid. The visual specification gives the
        /// two card sizes and their radius (§3) and the type and component values
        /// the card is built from (§2, §4), but not the rhythm inside it, so — as
        /// with `Dropdown` and `WindowRow` above — these are read off the
        /// `widget-small--*` and `widget-medium--*` mockups at 2× and declared here
        /// rather than inlined, per §5.
        ///
        /// The tile is one view shared by both families: the same status line,
        /// numerals, rule, caption and transport, laid out identically whether it
        /// occupies all 170 pt of a small card or the leading 151 pt of a medium
        /// one. The medium mockups draw that stack about 6 pt higher than the small
        /// ones do for no reason the specification names, and two tiles that differ
        /// by six points is a difference the user would see when both widgets are on
        /// the same desktop. One tile, measured off the small mockups — which sum to
        /// the card's 170 pt exactly — is the reading that keeps the surfaces
        /// agreeing with each other.
        enum Widget {
            /// The card's own inset, on all four edges.
            static let padding: CGFloat = 16
            /// From the card's leading text column to the medium's context pane.
            static let columnGap: CGFloat = 19

            // The tile, top to bottom. These sum with `padding` to exactly 170.
            /// `● ends 2:27 PM`.
            static let statusRowHeight: CGFloat = 16
            static let statusDotSize: CGFloat = 7
            static let statusDotGap: CGFloat = 7
            /// Holds the 44 pt numerals on their own baseline.
            static let numeralsRowHeight: CGFloat = 53
            static let numeralsToRule: CGFloat = 5
            static let ruleToCaption: CGFloat = 9
            /// `Ready` · the session's name · `Complete · 25 min`.
            static let captionRowHeight: CGFloat = 16
            static let captionToButtons: CGFloat = 4

            /// Above `Component.widgetTapTarget`, which is the floor rather than the
            /// size.
            static let buttonHeight: CGFloat = 31
            static let buttonGap: CGFloat = 6
            /// The transport's second control — `↺` and `+5` — held to one width so
            /// the primary beside it does not resize with its label.
            static let secondaryButtonWidth: CGFloat = 44
            /// §4's primary padding is the window's; a 32 pt inset on a 151 pt
            /// column leaves no room for a label. The mockups measure the widget's
            /// primary at this, where it has room to hug rather than to fill.
            static let primaryButtonPadding: CGFloat = 26

            // The medium's context pane: `IN SESSION` / `SESSION COMPLETE` over the
            // session's name and when it started.
            /// The tile's column. The pane takes what is left of the card less
            /// `columnGap`, which is 162 — the width the mockups measure it at.
            static let tileWidth: CGFloat = 151
            /// Both pane forms start below the card's `padding`, not at it: the
            /// mockups drop the pane clear of the tile's status line so the two
            /// columns read as a clock and a note about it rather than as two lists.
            static let paneTopInset: CGFloat = 14
            static let paneHeight: CGFloat = 79
            static let paneRadius: CGFloat = 10
            static let panePadding: CGFloat = 13
            static let paneLabelToTitle: CGFloat = 9
            static let paneTitleToMeta: CGFloat = 6
            static let paneBorderWidth: CGFloat = 1

            // The medium's suggestion rows, drawn in place of the pane while idle.
            static let suggestionsTopInset: CGFloat = 7
            /// `Component.widgetTapTarget` exactly. The mockups draw 28, which §4's
            /// 30 pt floor overrides — a row that is a single App Intent is a tap
            /// target like any other.
            static let suggestionRowHeight: CGFloat = DesignTokens.Component.widgetTapTarget
            static let suggestionRowGap: CGFloat = 5
            static let suggestionRowPadding: CGFloat = 8
            /// The colour bar leading every row, reserved even for a duration row so
            /// a meeting row among them shifts no title sideways.
            static let suggestionBarHeight: CGFloat = 16
            static let suggestionBarGap: CGFloat = 8
            /// At most three rows fit the card; the derivation offers no more.
            static let suggestionRowLimit = 3
        }

        /// The settings pane (`Settings` scene, `⌘,`), which holds the one set-once
        /// preference the product has: launch at login. D8 keeps it out of the dropdown
        /// sheet — that sheet is per-session actions — and §3.1's row grid has no slot
        /// for it, so it gets the platform's own home for a preference.
        ///
        /// **The visual specification describes no settings surface**, and these values
        /// are therefore not read off a mockup like `Dropdown` and `WindowRow` are.
        /// They are composed from rhythm that already exists: the sheet's own
        /// horizontal inset and row height, and a width narrow enough that the pane
        /// reads as one switch rather than as a preferences window with one thing in
        /// it. Nothing here is a new metric; it is existing metrics arranged.
        enum Settings {
            static let width: CGFloat = 320
            static var padding: CGFloat { Dropdown.horizontalPadding }
            static var rowHeight: CGFloat { Dropdown.footerHeight }
            static var captionGap: CGFloat { Dropdown.rowsTopPadding }
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

    /// `RRGGBB`, as the calendar snapshot stores a source calendar's color. Here
    /// rather than beside the calendar views because the widget extension draws the
    /// same bars from the same record.
    init?(hexString: String) {
        let digits = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// The `rgba(235,235,245,…)` label white the text levels are built from.
    fileprivate init(labelWhite opacity: Double) {
        self.init(.sRGB, red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: opacity)
    }
}
