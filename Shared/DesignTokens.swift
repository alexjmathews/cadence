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
        /// Stroked at `Component.windowRingWidth` around the window, containing it
        /// against a light desktop.
        static let windowRing = Color(.sRGB, white: 0, opacity: 0.30)
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
        /// Calendar event color bar and event-named sessions.
        static let event = Color(hex: 0xFF8A3D)

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
        static let windowNumerals = Font.system(size: 92, weight: .medium, design: .monospaced)
        static let windowNumeralsTracking: CGFloat = -6
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
        static let windowSize = CGSize(width: 520, height: 414)
        static let windowRadius: CGFloat = 12
        static let dropdownWidth: CGFloat = 272
        static let dropdownRadius: CGFloat = 12
        static let statusItemHeight: CGFloat = 28
        static let statusItemPillRadius: CGFloat = 5
        static let smallWidgetSize = CGSize(width: 170, height: 170)
        static let mediumWidgetSize = CGSize(width: 364, height: 170)
        static let widgetRadius: CGFloat = 22

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
