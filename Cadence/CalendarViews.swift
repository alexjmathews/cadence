import SwiftUI

/// The window's 68 pt footer, now with a calendar in it.
///
/// Its height was already real in stage 2 and nothing here changes it: the bar, the
/// text column and the trailing controls sit where the empty state put them, so a
/// dismissal that promotes the next event moves the *contents* of a fixed row and
/// nothing else. The trailing controls swap between two fixed-width groups for the
/// same reason — `Timer until 3:30` is a reserved width, not a width its label
/// decides (§3.1).
struct CalendarStrip: View {
    let content: StripContent
    let start: () -> Void
    let dismiss: () -> Void
    let toggleDayList: () -> Void
    let refresh: () -> Void
    let connect: () -> Void

    private typealias Row = DesignTokens.Layout.WindowRow

    var body: some View {
        HStack(spacing: 0) {
            bar

            text

            Spacer(minLength: Row.stripControlGap)

            trailing
        }
        .padding(.horizontal, Row.stripHorizontalPadding)
        .frame(height: Row.calendarStripHeight)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.Surface.fillStrip)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.Surface.hairline)
                .frame(height: DesignTokens.Component.hairlineWidth)
        }
    }

    /// The event's source-calendar colour when there is an event, and the strip's own
    /// hairline weight when there is not — the slot is occupied either way, so the
    /// text column never shifts.
    private var bar: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Component.eventColorBarRadius)
            .fill(content.row?.barColor ?? DesignTokens.Surface.hairline)
            .frame(
                width: DesignTokens.Component.eventColorBarWidth,
                height: Row.stripBarHeight
            )
            .padding(.trailing, Row.stripBarGap)
    }

    @ViewBuilder
    private var text: some View {
        if let row = content.row {
            VStack(alignment: .leading, spacing: Row.stripTitleToMetaGap) {
                Text(row.title)
                    .font(DesignTokens.Typography.stripEventTitle)
                    .foregroundStyle(row.titleColor)
                Text(row.metaText)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.TextColor.secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
        } else {
            // Placeholder copy, not an event title: the mockup draws it in the regular
            // body face (§2's Body 13/400), and the semibold event face measured 24 pt
            // wider than the mockup for the identical string. The strip's *real* event
            // title keeps the semibold face above.
            Text(emptyCopy)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.TextColor.quaternary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// §3.3: the strip describes what is *next*, and reaches its empty state both
    /// when the day is genuinely empty and when everything left has been dismissed —
    /// so "nothing else" is the wording true in both cases. A revoked calendar lands
    /// here too rather than on stale events (§2.3).
    private var emptyCopy: String {
        switch content {
        case .connect: "Connect your calendar to see today's events"
        case .denied: "Nothing else on your calendar today"
        case .empty: "Nothing else on your calendar today"
        case .event: ""
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch content {
        case .connect:
            // No `☰` here: there is no day to list yet, and the copy needs the room.
            action("Connect", width: Row.stripActionWidth, action: connect)
        case .denied, .empty:
            refreshButton
            allEvents
        case .event(let row):
            // The action is absent while a session runs — the mockup's
            // `--running-meeting-session` strip keeps the event and drops the button —
            // and its width is not reclaimed, so the two icons stay put.
            if let title = row.actionText {
                action(title, width: Row.stripActionWidth, action: start)
            } else {
                Color.clear.frame(width: Row.stripActionWidth, height: Row.stripActionHeight)
            }
            dayListToggle
            icon("xmark", label: "Dismiss event", action: dismiss)
        }
    }

    /// Only ever the *showing* direction: expanding the list swaps the whole view for
    /// `DayList`, whose own way back is `Back to timer`, so there is no state in which
    /// this button hides anything.
    private var dayListToggle: some View {
        icon("line.3.horizontal", label: "Show all events", action: toggleDayList)
    }

    private var refreshButton: some View {
        Button(action: refresh) {
            Image(systemName: "arrow.clockwise")
                .font(DesignTokens.Typography.micro)
                .frame(
                    width: DesignTokens.Component.refreshIconButtonSize,
                    height: DesignTokens.Component.refreshIconButtonSize
                )
        }
        .buttonStyle(StripControlStyle(radius: DesignTokens.Component.refreshIconButtonRadius))
        .padding(.leading, Row.stripControlGap)
        .accessibilityLabel("Refresh calendar")
    }

    private var allEvents: some View {
        Button(action: toggleDayList) {
            HStack(spacing: Row.stripAllEventsGap) {
                Text("All events")
                    .font(DesignTokens.Typography.stripEventTitle)
                Image(systemName: "line.3.horizontal")
                    .font(DesignTokens.Typography.body)
            }
            .frame(
                width: Row.stripAllEventsWidth,
                height: DesignTokens.Component.stripIconButtonSize
            )
        }
        .buttonStyle(StripControlStyle(radius: DesignTokens.Component.stripIconButtonRadius))
        .padding(.leading, Row.stripControlGap)
        .accessibilityLabel("All events")
    }

    private func icon(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(DesignTokens.Typography.body)
                .frame(
                    width: DesignTokens.Component.stripIconButtonSize,
                    height: DesignTokens.Component.stripIconButtonSize
                )
        }
        // Unboxed, unlike the empty state's `⟳` and `All events ☰`: the
        // `timer-window--idle-with-event` mockup draws these two as bare glyphs on the
        // strip's own wash, which is what keeps the event row's one *filled* control —
        // `Timer until 3:30` — reading as the action.
        .buttonStyle(BareIconStyle(radius: DesignTokens.Component.stripIconButtonRadius))
        .padding(.leading, Row.stripControlGap)
        .accessibilityLabel(label)
    }

    private func action(
        _ title: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(StripActionStyle(width: width))
            .padding(.leading, Row.stripControlGap)
    }
}

// MARK: - Day list

/// Every timed event today, drawn over the timer by `☰`.
///
/// It replaces the rows above the strip rather than growing the window: the footer
/// stays where it is, the top inset is the timer's own, and `Back to timer` returns.
/// Dismissed rows stay in the list — struck through, with the bar at 40% and the
/// title at `TextColor.dismissed` (§1.2) — because the list is where a dismissal is
/// undone.
///
/// **The rows scroll** (§3.1). The window's minimum is 520 × 414 and the grid leaves
/// the list 257.5 pt between the header and the footer, which is 5.85 rows: a
/// six-event day laid out as a plain stack pushed the tally, `Back to timer` and its
/// own header off both edges of the window. The header and the 68 pt footer are
/// pinned and only the rows move, which is the mockup's composition at any length of
/// day rather than only at the four events it happens to draw.
struct DayList: View {
    let content: DayListContent
    let access: CalendarAccess
    let start: (String) -> Void
    let dismiss: (String) -> Void
    let restore: (String) -> Void
    let refresh: () -> Void
    let close: () -> Void

    private typealias List = DesignTokens.Layout.DayList
    private typealias Row = DesignTokens.Layout.WindowRow

    var body: some View {
        VStack(spacing: 0) {
            // Fixed, not a `Spacer`: a flexible one competes with the rows region for
            // any extra window height and slides the header down as the window grows.
            // It is the timer's own inset, which is what keeps the first row on the
            // same column the strip's bar sits on.
            Color.clear.frame(height: Row.contentTopInset)

            header

            Rectangle()
                .fill(DesignTokens.Surface.hairline)
                .frame(height: DesignTokens.Component.hairlineWidth)

            rows

            footer
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(content.headerText)
                .font(DesignTokens.Typography.sectionLabel)
                .tracking(DesignTokens.Typography.sectionLabelTracking)
                .foregroundStyle(DesignTokens.TextColor.secondary)

            Spacer(minLength: Row.stripControlGap)

            if let synced = content.syncedText {
                Text(synced)
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.TextColor.quaternary)
            }

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Typography.micro)
                    .frame(
                        width: DesignTokens.Component.refreshIconButtonSize,
                        height: DesignTokens.Component.refreshIconButtonSize
                    )
            }
            .buttonStyle(StripControlStyle(radius: DesignTokens.Component.refreshIconButtonRadius))
            .padding(.leading, Row.stripBarGap)
            .accessibilityLabel("Refresh calendar")
        }
        .padding(.horizontal, Row.stripHorizontalPadding)
        .frame(height: List.headerHeight)
    }

    /// Top-aligned and scrolling: a short day leaves space below the last row rather
    /// than spreading four events over the window's height, and a long one scrolls
    /// inside the region the grid gives it rather than overflowing the window.
    private var rows: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                if access != .authorized {
                    placeholder("Cadence has no access to your calendar")
                } else if content.rows.isEmpty {
                    placeholder("Nothing on your calendar today")
                } else {
                    ForEach(content.rows) { row in
                        DayListRow(
                            row: row,
                            start: { start(row.id) },
                            dismiss: { dismiss(row.id) },
                            restore: { restore(row.id) }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .padding(.top, List.headerToRowsGap)
        // The one region that takes the window's extra height, and the one that gives
        // it up: below the default height there is nothing left to give, which is
        // exactly when the scroll view earns its place.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The list's two non-row states, on the row's own height and column so the
    /// header and footer do not move between them.
    private func placeholder(_ copy: String) -> some View {
        Text(copy)
            .font(DesignTokens.Typography.body)
            .foregroundStyle(DesignTokens.TextColor.quaternary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Row.stripHorizontalPadding)
            .frame(height: List.rowHeight)
    }

    /// The strip's own 68 pt, holding the day's tally and the way back. The bar slot
    /// is kept so the footer sits on the same column the timer's strip does.
    private var footer: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: DesignTokens.Component.eventColorBarRadius)
                .fill(DesignTokens.Surface.hairline)
                .frame(
                    width: DesignTokens.Component.eventColorBarWidth,
                    height: Row.stripBarHeight
                )
                .padding(.trailing, Row.stripBarGap)

            Text(content.footerText)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.TextColor.secondary)
                .lineLimit(1)

            Spacer(minLength: Row.stripControlGap)

            Button("Back to timer", action: close)
                .buttonStyle(
                    StripActionStyle(
                        width: List.backButtonWidth,
                        height: List.backButtonHeight,
                        label: DesignTokens.TextColor.primary,
                        border: DesignTokens.Surface.hairline
                    )
                )
        }
        .padding(.horizontal, Row.stripHorizontalPadding)
        .frame(height: Row.calendarStripHeight)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.Surface.fillStrip)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.Surface.hairline)
                .frame(height: DesignTokens.Component.hairlineWidth)
        }
    }
}

/// One event: colour bar, time column, title, and the row's one action.
///
/// The time sits in a fixed column so every title starts on the same edge, and the
/// action is trailing-aligned so `Undo hide` and `Start 120m` share an edge too.
private struct DayListRow: View {
    let row: EventRow
    let start: () -> Void
    let dismiss: () -> Void
    let restore: () -> Void

    private typealias List = DesignTokens.Layout.DayList
    private typealias Row = DesignTokens.Layout.WindowRow

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: DesignTokens.Component.eventColorBarRadius)
                .fill(row.barColor)
                .frame(
                    width: DesignTokens.Component.eventColorBarWidth,
                    height: List.rowBarHeight
                )
                .padding(.trailing, List.rowBarGap)

            Text(row.timeText)
                .font(DesignTokens.Typography.listTime)
                .monospacedDigit()
                .foregroundStyle(
                    row.isDismissed
                        ? DesignTokens.TextColor.dismissed
                        : DesignTokens.TextColor.secondary
                )
                .frame(width: List.timeColumnWidth, alignment: .leading)
                .padding(.trailing, List.timeToTitleGap)

            Text(row.title)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(row.titleColor)
                .strikethrough(row.isDismissed)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: DesignTokens.Component.listRowGap)

            action
        }
        .padding(.horizontal, Row.stripHorizontalPadding)
        .frame(height: List.rowHeight)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: DesignTokens.Component.listRowRadius)
                    .fill(DesignTokens.Surface.fillHover)
                    .padding(.horizontal, DesignTokens.Component.listRowPadding.leading)
            }
        }
        .onHover { isHovering = $0 }
    }

    /// A dismissed row offers the way back; a live one offers the timer. A row that
    /// is neither — a session is running, or the event is too close to time against —
    /// offers hiding it, which is legal in every state because it changes only what
    /// the strip suggests next.
    @ViewBuilder
    private var action: some View {
        if row.isDismissed {
            Button("Undo hide", action: restore)
                .buttonStyle(DayListActionStyle(color: DesignTokens.TextColor.secondary))
        } else if let title = row.listActionText {
            Button(title, action: start)
                .buttonStyle(DayListActionStyle(color: DesignTokens.Accent.base))
        } else {
            Button("Hide", action: dismiss)
                .buttonStyle(DayListActionStyle(color: DesignTokens.TextColor.quaternary))
        }
    }
}

// MARK: - Styles

/// A glyph with no chip behind it until the pointer arrives.
private struct BareIconStyle: ButtonStyle {
    let radius: CGFloat

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DesignTokens.TextColor.secondary)
            .background(
                isHovering ? DesignTokens.Surface.fillHover : .clear,
                in: .rect(cornerRadius: radius)
            )
            .opacity(configuration.isPressed ? DesignTokens.Component.pressedOpacity : 1)
            .onHover { isHovering = $0 }
    }
}

private struct StripControlStyle: ButtonStyle {
    let radius: CGFloat

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DesignTokens.TextColor.quaternary)
            .background(
                isHovering ? DesignTokens.Surface.fillHover : DesignTokens.Surface.fillSubtle,
                in: .rect(cornerRadius: radius)
            )
            .opacity(configuration.isPressed ? DesignTokens.Component.pressedOpacity : 1)
            .onHover { isHovering = $0 }
    }
}

/// `Timer until 3:30` and `Back to timer`: a fixed-width filled control, so the
/// strip's trailing edge does not move when the label does.
private struct StripActionStyle: ButtonStyle {
    var width: CGFloat
    var height: CGFloat = DesignTokens.Layout.WindowRow.stripActionHeight
    var label: Color = DesignTokens.Accent.text
    var border: Color = DesignTokens.Accent.stripAction

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Component.listRowRadius)

        return configuration.label
            .font(DesignTokens.Typography.compactButton)
            .foregroundStyle(label)
            .frame(width: width, height: height)
            .background(
                isHovering ? DesignTokens.Surface.fillHover : DesignTokens.Surface.fillStripAction,
                in: shape
            )
            .overlay {
                shape.strokeBorder(border, lineWidth: DesignTokens.Component.hairlineWidth)
            }
            .opacity(configuration.isPressed ? DesignTokens.Component.pressedOpacity : 1)
            .onHover { isHovering = $0 }
    }
}

private struct DayListActionStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.stripEventTitle)
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? DesignTokens.Component.pressedOpacity : 1)
    }
}
