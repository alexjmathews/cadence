import SwiftUI

/// The 272 pt sheet behind the status item (D6): numerals and status word, the
/// progress rule, the transport, the quick-duration rows, and `Open Cadence`.
///
/// Everything it shows is derived from `controller.state` at `controller.now`, and
/// every control calls a transition on the controller. The view holds no session
/// state of its own.
struct MenuBarDropdown: View {
    let controller: SessionController

    @Environment(\.openWindow) private var openWindow

    private typealias Sheet = DesignTokens.Layout.Dropdown

    var body: some View {
        let status = controller.status

        VStack(spacing: 0) {
            header(status)
            progressRule(status)
            actions(status)

            divider()

            presets(status)

            divider()

            footer()
        }
        .frame(width: DesignTokens.Layout.dropdownWidth)
        .background(shell(status))
    }

    // MARK: - Shell

    /// The whole sheet recolors on completion, per the visual spec's state rule.
    private func shell(_ status: SessionStatus) -> Color {
        status == .complete ? DesignTokens.Surface.complete : DesignTokens.Surface.base
    }

    private func accent(_ status: SessionStatus) -> Color {
        status == .complete ? DesignTokens.Accent.complete : DesignTokens.Accent.base
    }

    private func divider() -> some View {
        Rectangle()
            .fill(DesignTokens.Surface.hairline)
            .frame(height: DesignTokens.Component.hairlineWidth)
            .padding(.horizontal, Sheet.controlPadding)
    }

    // MARK: - Header

    private func header(_ status: SessionStatus) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: Sheet.controlPadding) {
            Text(controller.clockText)
                .font(DesignTokens.Typography.dropdownNumerals)
                .tracking(DesignTokens.Typography.dropdownNumeralsTracking)
                .monospacedDigit()
                .foregroundStyle(
                    status == .complete
                        ? DesignTokens.Accent.completeText
                        : DesignTokens.TextColor.primary
                )

            Spacer(minLength: 0)

            Text(StatusWord.text(for: controller.state, at: controller.now))
                .font(DesignTokens.Typography.body)
                .foregroundStyle(
                    status == .complete
                        ? DesignTokens.Accent.completeText
                        : DesignTokens.TextColor.secondary
                )
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.top, Sheet.topPadding)
        .padding(.horizontal, Sheet.horizontalPadding)
        .frame(height: Sheet.topPadding + Sheet.headerHeight, alignment: .bottom)
    }

    // MARK: - Progress

    private func progressRule(_ status: SessionStatus) -> some View {
        let radius = DesignTokens.Component.compactProgressRuleRadius

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: radius)
                .fill(DesignTokens.Surface.progressTrack)

            GeometryReader { proxy in
                let width = proxy.size.width * controller.state.progress(controller.now)
                // Below a rounded rectangle's own corner diameter the fill degrades
                // to a dot in the track's left cap, which reads as progress that
                // has not happened. A session at zero shows an empty rule.
                if width >= DesignTokens.Component.compactProgressRuleHeight {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(accent(status))
                        .frame(width: width)
                }
            }
        }
        .frame(height: DesignTokens.Component.compactProgressRuleHeight)
        .padding(.top, Sheet.headerToRule)
        .padding(.horizontal, Sheet.horizontalPadding)
    }

    // MARK: - Actions

    @ViewBuilder
    private func actions(_ status: SessionStatus) -> some View {
        HStack(spacing: Sheet.actionGap) {
            switch status {
            case .idle:
                primary("Start", status: status, action: controller.start)
            case .running:
                primary("Pause", status: status, action: controller.pause)
                secondary("Reset", action: controller.reset)
            case .paused:
                primary("Resume", status: status, action: controller.resume)
                secondary("Reset", action: controller.reset)
            case .complete:
                primary("Start another", status: status, action: controller.startAnother)
                secondary("+5 min", action: controller.extend)
            }
        }
        .frame(height: Sheet.actionHeight)
        .padding(.top, Sheet.ruleToActions)
        .padding(.bottom, Sheet.actionsToDivider)
        .padding(.horizontal, Sheet.controlPadding)
    }

    private func primary(
        _ title: String,
        status: SessionStatus,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(
                FilledActionStyle(
                    fill: accent(status),
                    label: status == .complete
                        ? DesignTokens.TextColor.onComplete
                        : DesignTokens.TextColor.onAccent
                )
            )
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(OutlinedActionStyle())
    }

    // MARK: - Presets

    /// Duration selection is legal only in `idle` (§5), so the rows render
    /// identically in every state but respond in one — the list is a reminder of
    /// what is on offer while a session runs, not a second way to retime it.
    private func presets(_ status: SessionStatus) -> some View {
        VStack(spacing: 0) {
            ForEach(controller.presets) { preset in
                PresetRow(preset: preset, isSelectable: status == .idle) {
                    controller.select(preset)
                }
            }

            // The calendar lands in a later stage; until then the row the events
            // would occupy carries the empty copy.
            Text("Nothing on your calendar today")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.TextColor.quaternary)
                .frame(
                    maxWidth: .infinity,
                    minHeight: Sheet.rowHeight,
                    alignment: .leading
                )
                .padding(.horizontal, Sheet.horizontalPadding)
        }
        .padding(.top, Sheet.rowsTopPadding)
        .padding(.bottom, Sheet.rowsBottomPadding)
    }

    // MARK: - Footer

    /// Two rows: reveal the window, and leave. `Quit Cadence` is not in the mockup
    /// but D8 puts it here, because a menu-bar-only app that is never opened has no
    /// other way out — `⌘Q` needs a main menu, which an `.accessory` app does not
    /// have. The sheet is one row taller than the mockup as a result.
    @ViewBuilder
    private func footer() -> some View {
        footerRow("Open Cadence", shortcut: "⌘O") {
            AppActivation.showMainWindow(openWindow: openWindow)
        }
        .keyboardShortcut("o")

        // No `.keyboardShortcut("q")`: it was verified not to fire from this panel,
        // and a modifier that does nothing is worse than none. The hint still
        // earns its place — `⌘Q` is what quits once the window is open.
        footerRow("Quit Cadence", shortcut: "⌘Q") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func footerRow(
        _ title: String,
        shortcut: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(title)
                    .foregroundStyle(DesignTokens.TextColor.primary)
                Spacer(minLength: DesignTokens.Component.listRowGap)
                Text(shortcut)
                    .foregroundStyle(DesignTokens.TextColor.tertiary)
            }
            .font(DesignTokens.Typography.body)
            .padding(.horizontal, Sheet.horizontalPadding)
            .frame(height: Sheet.footerHeight)
        }
        .buttonStyle(SheetRowStyle())
    }
}

// MARK: - Rows

private struct PresetRow: View {
    let preset: DurationPreset
    let isSelectable: Bool
    let action: () -> Void

    private typealias Sheet = DesignTokens.Layout.Dropdown

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // The event color bar's slot, held empty. A meeting row joins this
                // list in a later stage and no title moves when it does.
                Color.clear
                    .frame(width: DesignTokens.Component.eventColorBarWidth)
                    .padding(.trailing, Sheet.rowBarGap)

                Text(preset.title)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.TextColor.primary)
                Spacer(minLength: DesignTokens.Component.listRowGap)
                Text("\(preset.minutes) min")
                    .font(DesignTokens.Typography.chipMeta)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.TextColor.tertiary)
            }
            .padding(.horizontal, Sheet.horizontalPadding)
            .frame(height: Sheet.rowHeight)
        }
        // `.disabled` rather than `.allowsHitTesting(false)`: the latter stops the
        // pointer but leaves the control advertising itself as enabled, so
        // assistive technology can still press a row §5 makes illegal. The colors
        // above are set explicitly, so the rows keep their appearance either way.
        .buttonStyle(SheetRowStyle(isEnabled: isSelectable))
        .disabled(!isSelectable)
    }
}

// MARK: - Button styles

/// A full-bleed row that lights up under the pointer. Disabled rows keep their
/// colors — the list is still information when it is not a control.
private struct SheetRowStyle: ButtonStyle {
    var isEnabled = true

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .background {
                if isEnabled, isHovering || configuration.isPressed {
                    RoundedRectangle(cornerRadius: DesignTokens.Component.listRowRadius)
                        .fill(DesignTokens.Surface.fillHover)
                        .padding(.horizontal, DesignTokens.Layout.Dropdown.controlPadding)
                }
            }
            .opacity(configuration.isPressed ? DesignTokens.Component.pressedOpacity : 1)
            .onHover { isHovering = $0 }
    }
}

private struct FilledActionStyle: ButtonStyle {
    let fill: Color
    let label: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.compactButton)
            .foregroundStyle(label)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                fill,
                in: .rect(cornerRadius: DesignTokens.Component.secondaryButtonRadius)
            )
            .opacity(configuration.isPressed ? DesignTokens.Component.pressedOpacity : 1)
    }
}

private struct OutlinedActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Component.secondaryButtonRadius)

        return configuration.label
            .font(DesignTokens.Typography.compactButton)
            .foregroundStyle(DesignTokens.TextColor.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.Surface.fillSubtle, in: shape)
            .overlay {
                shape.strokeBorder(
                    DesignTokens.Surface.hairline,
                    lineWidth: DesignTokens.Component.secondaryButtonBorderWidth
                )
            }
            .opacity(configuration.isPressed ? DesignTokens.Component.pressedOpacity : 1)
    }
}

/// Reveals the main window from the menu bar: promotes the app out of accessory
/// so it can take focus, then opens the window.
enum AppActivation {
    @MainActor
    static func showMainWindow(openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: WindowID.main)
    }
}
