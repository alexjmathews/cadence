import SwiftUI
import WidgetKit

// In the extension these views compile alongside `Shared/`; in `CadenceTests` they
// compile against the host app's copy of it, so `WidgetGeometryTests` can render the
// real views rather than a stand-in. Nothing else differs between the two builds.
#if CADENCE_TESTS
@testable import Cadence
#endif

/// The two families, drawn from a `WidgetTile` and a `WidgetPane`. Everything these
/// views decide is geometry and colour; what to show was decided in
/// `WidgetPresentation`, and every control is one `WidgetAction` behind one App
/// Intent (§4).

private typealias Grid = DesignTokens.Layout.Widget

// MARK: - Shell

/// The state-driven shell colours. The whole card recolors on completion, as every
/// other surface does, and it is derived from `effectiveStatus` rather than the
/// stored value (§5's implementation note, D4).
private struct WidgetShell {
    let status: SessionStatus

    var isComplete: Bool { status == .complete }

    var background: Color {
        isComplete ? DesignTokens.Surface.complete : DesignTokens.Surface.base
    }

    var accent: Color {
        isComplete ? DesignTokens.Accent.complete : DesignTokens.Accent.base
    }

    var numerals: Color {
        isComplete ? DesignTokens.Accent.completeText : DesignTokens.TextColor.primary
    }

    var caption: Color {
        isComplete ? DesignTokens.Accent.completeCaption : DesignTokens.TextColor.secondary
    }

    /// The transport's primary label, which sits on the accent in both shells.
    var onAccent: Color {
        isComplete ? DesignTokens.TextColor.onComplete : DesignTokens.TextColor.onAccent
    }

    var paneFill: Color {
        isComplete ? DesignTokens.Surface.fillComplete : DesignTokens.Surface.fillSubtle
    }

    var paneBorder: Color {
        isComplete ? DesignTokens.Surface.hairlineComplete : DesignTokens.Surface.hairline
    }

    var paneLabel: Color {
        isComplete ? DesignTokens.Accent.complete : DesignTokens.Accent.text
    }
}

// MARK: - Tile

/// The leading column: `● ends 2:27 PM`, the numerals, the rule, the caption, the
/// transport. One view for both families, so a user with both widgets installed sees
/// one clock rather than two that disagree by a few points.
struct WidgetTileView: View {
    let tile: WidgetTile
    /// True in the small card, whose transport has the whole column to fill.
    var fillsTransportWidth = false

    private var shell: WidgetShell { WidgetShell(status: tile.status) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusRow
            numerals
            rule
                .padding(.top, Grid.numeralsToRule)
            caption
                .padding(.top, Grid.ruleToCaption)
            transport
                .padding(.top, Grid.captionToButtons)
        }
    }

    // MARK: Status

    /// The mark and the clock the state is oriented around. The row keeps its height
    /// even with nothing to say, which is what stops the numerals sliding up on an
    /// idle day with no suggestion left.
    private var statusRow: some View {
        HStack(spacing: Grid.statusDotGap) {
            if let statusText = tile.statusText {
                Circle()
                    .fill(shell.accent)
                    .frame(width: Grid.statusDotSize, height: Grid.statusDotSize)

                Text(statusText)
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.TextColor.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        // Reserved, not conditional: the row keeps its height with nothing in it, so
        // an idle day with no suggestion left does not slide the numerals up 16 pt.
        .frame(height: Grid.statusRowHeight)
    }

    // MARK: Numerals

    @ViewBuilder
    private var numerals: some View {
        Group {
            switch tile.countdown {
            case .interval(let range):
                // SwiftUI counts this one itself (P1). Nothing in the extension has
                // to be awake for the digits to be right, which is the whole reason
                // the widget needs no ticker.
                Text(timerInterval: range, countsDown: true)
            case .text(let text):
                Text(text)
            }
        }
        .font(DesignTokens.Typography.widgetNumerals)
        .tracking(DesignTokens.Typography.widgetNumeralsTracking)
        .monospacedDigit()
        .foregroundStyle(shell.numerals)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(height: Grid.numeralsRowHeight, alignment: .center)
    }

    // MARK: Progress

    private var rule: some View {
        let radius = DesignTokens.Component.compactProgressRuleRadius

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: radius)
                .fill(DesignTokens.Surface.progressTrack)

            GeometryReader { proxy in
                let width = proxy.size.width * tile.progress
                // Below the rule's own corner diameter the fill degrades to a dot in
                // the track's left cap, which reads as progress that has not
                // happened — the dropdown's rule declines on the same terms.
                if width >= DesignTokens.Component.compactProgressRuleHeight {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(shell.accent)
                        .frame(width: width)
                }
            }
        }
        .frame(height: DesignTokens.Component.compactProgressRuleHeight)
    }

    // MARK: Caption

    private var caption: some View {
        Text(tile.caption)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(shell.caption)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: Grid.captionRowHeight, alignment: .leading)
    }

    // MARK: Transport

    /// One intent per control (§4), each at least `widgetTapTarget` tall.
    private var transport: some View {
        HStack(spacing: Grid.buttonGap) {
            WidgetPrimaryButton(
                control: tile.primary,
                shell: shell,
                fillsWidth: fillsTransportWidth
            )

            if let secondary = tile.secondary {
                WidgetSecondaryButton(control: secondary, shell: shell)
            }
        }
        // The medium's transport takes its natural width and is allowed to run past
        // the tile's column: nothing sits beside it at that height — the pane ends
        // well above — and the mockups draw `Start another  +5` at 183 pt against a
        // 151 pt column. The small's fills instead, because there it *is* the column.
        //
        // The overflow is *anchored*, never centred, and that is a two-sided
        // property. Here the outer `maxWidth` pins the buttons to the column's
        // leading edge; the other side is `MediumWidgetView`'s `alignment: .leading`
        // on the tile's own `frame(width:)`, because a `fixedSize` child makes the
        // enclosing `VStack` report *its* width — 183, not 151 — and a centred
        // 151 pt frame would then pull the whole column 16 pt off the card.
        .fixedSize(horizontal: !fillsTransportWidth, vertical: false)
        .frame(height: Grid.buttonHeight)
        .frame(maxWidth: fillsTransportWidth ? nil : .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

private struct WidgetPrimaryButton: View {
    let control: WidgetControl
    let shell: WidgetShell
    /// The small card's transport spans the whole column, so the primary fills what
    /// the secondary leaves; the medium's has room to spare and hugs its label at
    /// `primaryButtonPadding`, which is how the mockups draw the same button at 138
    /// and at 124.
    let fillsWidth: Bool

    var body: some View {
        Button(intent: CadenceActionIntent(control.action)) {
            Text(control.title)
                .font(DesignTokens.Typography.compactButton)
                .foregroundStyle(shell.onAccent)
                .lineLimit(1)
                .padding(.horizontal, fillsWidth ? 0 : Grid.primaryButtonPadding)
                .frame(maxWidth: fillsWidth ? .infinity : nil, maxHeight: .infinity)
                .background(
                    shell.accent,
                    in: .rect(cornerRadius: DesignTokens.Component.primaryButtonRadius)
                )
        }
        .buttonStyle(.plain)
        .frame(minHeight: DesignTokens.Component.widgetTapTarget)
        .accessibilityLabel(control.title)
    }
}

private struct WidgetSecondaryButton: View {
    let control: WidgetControl
    let shell: WidgetShell

    var body: some View {
        Button(intent: CadenceActionIntent(control.action)) {
            Group {
                if control.isGlyph {
                    Image(systemName: "arrow.counterclockwise")
                        .font(DesignTokens.Typography.compactButton)
                } else {
                    // `+5 min` does not fit 44 pt; the mockups draw the number, and
                    // `control.title` stays the accessibility label.
                    Text(control.title.replacingOccurrences(of: " min", with: ""))
                        .font(DesignTokens.Typography.compactButton)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(DesignTokens.TextColor.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                DesignTokens.Surface.fillWidgetSecondary,
                in: .rect(cornerRadius: DesignTokens.Component.secondaryButtonRadius)
            )
        }
        .buttonStyle(.plain)
        // A fixed width so `↺` and `+5` are the same control, and so the primary
        // beside it does not resize with its own label.
        .frame(width: Grid.secondaryButtonWidth)
        .frame(minHeight: DesignTokens.Component.widgetTapTarget)
        .accessibilityLabel(control.title)
    }
}

// MARK: - Small

struct SmallWidgetView: View {
    let tile: WidgetTile

    var body: some View {
        WidgetTileView(tile: tile, fillsTransportWidth: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Grid.padding)
            .containerBackground(WidgetShell(status: tile.status).background, for: .widget)
    }
}

// MARK: - Medium

struct MediumWidgetView: View {
    let tile: WidgetTile
    let pane: WidgetPane

    private var shell: WidgetShell { WidgetShell(status: tile.status) }

    var body: some View {
        HStack(alignment: .top, spacing: Grid.columnGap) {
            WidgetTileView(tile: tile)
                // `.leading`, not the default centre: the transport is allowed to
                // overrun the column (see `WidgetTileView.transport`), and a centred
                // frame splits that overrun across both edges — which put the whole
                // complete-state column 16 pt off the leading edge of the card.
                .frame(width: Grid.tileWidth, alignment: .leading)

            paneColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Grid.padding)
        .containerBackground(shell.background, for: .widget)
    }

    @ViewBuilder
    private var paneColumn: some View {
        switch pane {
        case .suggestions(let rows):
            VStack(spacing: Grid.suggestionRowGap) {
                ForEach(rows) { row in
                    SuggestionRowView(row: row, shell: shell)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Grid.suggestionsTopInset)
            .frame(maxWidth: .infinity, alignment: .top)

        case .session(let label, let title, let meta):
            SessionPaneView(label: label, title: title, meta: meta, shell: shell)
                .padding(.top, Grid.paneTopInset)
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

/// `IN SESSION` / `SESSION COMPLETE` over the session's name and when it started.
private struct SessionPaneView: View {
    let label: String
    let title: String
    let meta: String?
    let shell: WidgetShell

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(DesignTokens.Typography.widgetPaneLabel)
                .tracking(DesignTokens.Typography.widgetPaneLabelTracking)
                .foregroundStyle(shell.paneLabel)
                .lineLimit(1)

            Text(title)
                .font(DesignTokens.Typography.stripEventTitle)
                .foregroundStyle(DesignTokens.TextColor.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, Grid.paneLabelToTitle)

            if let meta {
                Text(meta)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(shell.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, Grid.paneTitleToMeta)
            }

            Spacer(minLength: 0)
        }
        .padding(Grid.panePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Grid.paneHeight)
        .background(shell.paneFill, in: .rect(cornerRadius: Grid.paneRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Grid.paneRadius)
                .strokeBorder(shell.paneBorder, lineWidth: Grid.paneBorderWidth)
        }
    }
}

/// One suggestion row: a reserved colour bar, a title, and the length it is worth.
/// A row with an action is a single App Intent; the empty-calendar row is copy and
/// deliberately is not a button.
private struct SuggestionRowView: View {
    let row: WidgetSuggestion
    let shell: WidgetShell

    var body: some View {
        if let action = row.action {
            Button(intent: CadenceActionIntent(action)) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.title)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: DesignTokens.Component.eventColorBarRadius)
                .fill(barColor)
                .frame(
                    width: DesignTokens.Component.eventColorBarWidth,
                    height: Grid.suggestionBarHeight
                )
                .padding(.trailing, Grid.suggestionBarGap)

            // A control's title is one line and truncates; the empty-calendar copy is
            // a sentence and wraps, because `Nothing on your cal…` is not a sentence.
            Text(row.title)
                .font(
                    row.action == nil
                        ? DesignTokens.Typography.caption
                        : DesignTokens.Typography.body
                )
                .foregroundStyle(
                    row.action == nil
                        ? DesignTokens.TextColor.quaternary
                        : DesignTokens.TextColor.primary
                )
                .lineLimit(row.action == nil ? 2 : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: DesignTokens.Component.listRowGap)

            if let metaText = row.metaText {
                Text(metaText)
                    .font(DesignTokens.Typography.chipMeta)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.TextColor.tertiary)
            }
        }
        .padding(.horizontal, Grid.suggestionRowPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Grid.suggestionRowHeight)
        // Only the rows that *are* controls carry the fill. The copy row already
        // drops to caption weight over quaternary and reserves its colour bar as
        // `.clear`; the fill was the last cue still saying "press me" about a
        // sentence nothing happens when you press.
        .background(
            row.action == nil ? Color.clear : shell.paneFill,
            in: .rect(cornerRadius: DesignTokens.Component.listRowRadius)
        )
    }

    /// A meeting row inherits its source calendar's colour (§1.2); a duration row
    /// keeps the slot filled with a neutral mark, so no title moves when a meeting
    /// appears among them.
    private var barColor: Color {
        // Copy is not a row anything starts, so it carries no mark — but it keeps the
        // slot, so its text sits on the same column as the titles above it.
        guard row.action != nil else { return .clear }
        guard let hex = row.barColorHex else { return DesignTokens.Surface.widgetRowBar }
        return Color(hexString: hex) ?? DesignTokens.Accent.event
    }
}
