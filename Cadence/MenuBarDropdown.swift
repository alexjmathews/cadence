import SwiftUI

/// The 272 pt sheet behind the status item (D6): numerals and status word, the
/// progress rule, the transport, the quick-duration rows, and `Open Cadence`.
///
/// Everything it shows is derived from `controller.state` at `controller.now`, and
/// every control calls a transition on the controller. The view holds no session
/// state of its own.
struct MenuBarDropdown: View {
    let controller: SessionController
    let calendar: CalendarController

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

    /// The clock and the word beside it, and the one row D10 is about.
    ///
    /// A running session's word is its *title* (`StatusWord`), so this row pairs six
    /// monospaced glyphs with an arbitrary meeting name — and two `Text`s at equal
    /// layout priority negotiate, which is how a long title came to render the clock
    /// as `60:...`. The clock therefore takes its ideal width unconditionally
    /// (`.fixedSize`) *and* outranks the label, and the label truncates.
    ///
    /// The two are belt-and-braces, not two halves of one mechanism: at this sheet's
    /// width either alone is sufficient — dropping `.fixedSize` and keeping the priority
    /// still renders the whole clock, and `DropdownGeometryTests` fails only when both
    /// go. They are kept together because they refuse the compression differently, a
    /// priority ordering it and `.fixedSize` forbidding it.
    ///
    /// It is its own view, taking strings rather than the controller, so
    /// `DropdownGeometryTests` can render the real row at the real sheet width and
    /// measure where the ink lands. A layout rule nothing can measure is a layout
    /// rule that regresses silently — which is exactly how `60:...` shipped.
    struct DropdownHeader: View {
        let clockText: String
        let statusWord: String
        let status: SessionStatus
        /// The clock in words, for VoiceOver. Supplied by the caller rather than parsed
        /// back out of `clockText`, because the caller has the `TimeInterval` and the
        /// string is a two-digit-padded rendering of it. Defaults to empty so
        /// `DropdownGeometryTests` can render the row for its geometry alone.
        var spokenClock: String = ""

        private typealias Sheet = DesignTokens.Layout.Dropdown

        var body: some View {
            HStack(alignment: .lastTextBaseline, spacing: Sheet.controlPadding) {
                Text(clockText)
                    .font(DesignTokens.Typography.dropdownNumerals)
                    .tracking(DesignTokens.Typography.dropdownNumeralsTracking)
                    .monospacedDigit()
                    .foregroundStyle(
                        status == .complete
                            ? DesignTokens.Accent.completeText
                            : DesignTokens.TextColor.primary
                    )
                    .fixedSize()
                    .layoutPriority(DesignTokens.Clock.layoutPriority)

                Spacer(minLength: 0)

                Text(statusWord)
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
            // One stop, not two. The word beside the clock is the session's *name* while
            // running, so reading them separately gives a bare padded number and then a
            // bare title; read together they are the sentence the row is.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SpokenText.clockLabel(for: status))
            .accessibilityValue("\(spokenClock), \(statusWord)")
        }
    }

    private func header(_ status: SessionStatus) -> some View {
        DropdownHeader(
            clockText: controller.clockText,
            statusWord: StatusWord.text(for: controller.state, at: controller.now),
            status: status,
            spokenClock: SpokenText.duration(controller.state.remaining(controller.now))
        )
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
        // Same treatment as the window's rule: a value, no hint, and no animation to
        // suppress for Reduce Motion — the fill steps once a second off the ticker.
        .accessibilityElement()
        .accessibilityLabel("Session progress")
        .accessibilityValue(SpokenText.progress(controller.state.progress(controller.now)))
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
                primary("Reset", status: status, action: controller.reset)
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

            calendarRow(status)
        }
        .padding(.top, Sheet.rowsTopPadding)
        .padding(.bottom, Sheet.rowsBottomPadding)
    }

    // MARK: - Calendar

    /// One row, four states (§3.3). `To Design review` when there is something to
    /// time against; otherwise a row about *access*, because `Nothing on your
    /// calendar today` is a statement about the day and is simply false when Cadence
    /// has never been allowed to look at one.
    ///
    /// Unlike the clock targets above it the meeting row carries the buffer (D7): its
    /// whole point is not to still be running when the meeting starts.
    @ViewBuilder
    private func calendarRow(_ status: SessionStatus) -> some View {
        let content = CalendarPresentation.dropdownCalendar(
            access: calendar.access,
            suggestion: suggestion,
            buffer: controller.preferences.endEarlyBuffer,
            now: controller.now
        )

        switch content {
        case .meeting(let meeting):
            PresetRow(
                preset: meeting,
                isSelectable: status == .idle,
                barColor: suggestion.map(EventRow.barColor)
            ) {
                if let suggestion { startMeeting(suggestion.id) }
            }

        // The one connect affordance reachable without opening the window. It is a
        // control, not copy: pressing it is what raises the system prompt.
        case .connect:
            actionRow(content.copy ?? "", accent: true) {
                Task { await calendar.connect() }
            }

        // The prompt will not return for a denied user (EventKit refuses to ask
        // twice), so this row goes where the switch actually is.
        case .denied:
            actionRow(content.copy ?? "", accent: false) {
                calendar.openSystemSettings()
            }

        case .empty:
            Text(content.copy ?? "")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.TextColor.quaternary)
                .frame(
                    maxWidth: .infinity,
                    minHeight: Sheet.rowHeight,
                    alignment: .leading
                )
                .padding(.horizontal, Sheet.horizontalPadding)
        }
    }

    /// A calendar row that does something, on the same column and row height the
    /// presets use so the sheet's geometry does not depend on the access state.
    private func actionRow(
        _ title: String,
        accent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: DesignTokens.Component.eventColorBarWidth)
                    .padding(.trailing, Sheet.rowBarGap)

                Text(title)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(
                        accent
                            ? DesignTokens.Accent.text
                            : DesignTokens.TextColor.secondary
                    )
                    .lineLimit(1)

                Spacer(minLength: DesignTokens.Component.listRowGap)
            }
            .padding(.horizontal, Sheet.horizontalPadding)
            .frame(height: Sheet.rowHeight)
        }
        .buttonStyle(SheetRowStyle())
        .accessibilityLabel(title)
    }

    private var suggestion: EventOccurrence? {
        calendar.suggestion(
            buffer: controller.preferences.endEarlyBuffer,
            now: controller.now
        )
    }

    /// The same path the window's strip takes (P4): re-resolve the key against the
    /// live store, materialise `eventStart − buffer`, copy the title. Two surfaces,
    /// one derivation, so a meeting timer started here and one started from the
    /// window are the same state.
    private func startMeeting(_ key: String) {
        let buffer = controller.preferences.endEarlyBuffer
        // The re-resolution is a calendar fetch and so is awaited off the main actor;
        // the press is still what decides the instant, since `meetingStart` takes its
        // own `now` when it runs and the deadline is materialised from the live start.
        Task {
            guard let meeting = await calendar.meetingStart(for: key, buffer: buffer)
            else { return }
            controller.startMeeting(meeting)
        }
    }

    // MARK: - Footer

    /// Three rows: reveal the window, open the preferences pane, and leave.
    ///
    /// None of the three is in the mockup; D8 puts them here, because a menu-bar-only
    /// app that is never opened has no other way to reach any of them — `⌘Q` and `⌘,`
    /// both need a main menu, which an `.accessory` app does not have. The sheet is two
    /// rows taller than the mockup as a result.
    ///
    /// `Settings…` is the *door*, not the preference: D8 as amended in Stage 5 keeps
    /// launch-at-login behind the `Settings` scene (and `endEarlyBuffer` in the window's
    /// swap slot, where the mockups put it) and puts only the way in here. One row now
    /// serves any number of future preferences.
    @ViewBuilder
    private func footer() -> some View {
        footerRow("Open Cadence", shortcut: "⌘O") {
            AppActivation.showMainWindow(openWindow: openWindow)
        }
        .keyboardShortcut("o")

        // No `.keyboardShortcut(",")`, for the same reason as `⌘Q` below: both are
        // key equivalents AppKit routes through the App menu, which an `.accessory`
        // process does not have, and `⌘Q` was measured not to fire from this panel.
        // `⌘O` works because it is not one of those. The glyph still earns its place —
        // `⌘,` is what opens this pane once the window has promoted the app.
        footerRow("Settings…", shortcut: "⌘,") {
            AppActivation.showSettings()
        }

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
        // The shortcut glyphs are a hint at the keyboard, not part of the row's name:
        // read verbatim they come out as "command O" appended to every row.
        .accessibilityLabel(title)
    }
}

// MARK: - Rows

private struct PresetRow: View {
    let preset: DurationPreset
    let isSelectable: Bool
    /// A meeting row fills the reserved colour-bar slot with its source calendar's
    /// colour; a duration row leaves it empty, which is what keeps every title on the
    /// same column whether or not there is a meeting among them.
    var barColor: Color?
    let action: () -> Void

    private typealias Sheet = DesignTokens.Layout.Dropdown

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Group {
                    if let barColor {
                        RoundedRectangle(cornerRadius: DesignTokens.Component.eventColorBarRadius)
                            .fill(barColor)
                            .frame(height: Sheet.rowBarHeight)
                    } else {
                        Color.clear
                    }
                }
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
        // The visible row is a title and a length in two columns; read as two labels it
        // becomes "45 minutes, 45 min". One sentence, and it names the *act* — pressing
        // the row re-scopes the plan, it does not merely state a duration.
        .accessibilityLabel("Set duration to \(preset.title), \(preset.minutes) minutes")
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
            // The *primary* radius, though the two are equal today: this style draws the
            // sheet's primary action, and reading the secondary's token here would leave
            // the dropdown behind the window and the widget the moment they diverged.
            .background(
                fill,
                in: .rect(cornerRadius: DesignTokens.Component.primaryButtonRadius)
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

/// Reveals a window from the menu bar: promotes the app out of accessory
/// so it can take focus, then opens the window.
enum AppActivation {
    @MainActor
    static func showMainWindow(openWindow: OpenWindowAction) {
        promote()
        openWindow(id: WindowID.main)
    }

    /// Opens the `Settings` scene from the sheet (D8 as amended).
    ///
    /// There is no environment action for this that works from a `MenuBarExtra` — SwiftUI
    /// offers `SettingsLink`, but it is a view, and reusing `footerRow` is what keeps the
    /// three footer rows one row rather than two kinds of row that merely look alike. So
    /// this sends the AppKit action the standard `Cadence ▸ Settings…` item sends, which
    /// is the same door by a different handle. The older selector is tried as well: the
    /// action was renamed in macOS 13 and a process that answers only to the old name
    /// should still open its pane rather than silently do nothing.
    @MainActor
    static func showSettings() {
        // Promoted first for the same reason the main window is: an `.accessory`
        // process cannot bring a window to the front to be typed into.
        promote()
        let selectors = ["showSettingsWindow:", "showPreferencesWindow:"]
        for name in selectors where NSApp.sendAction(Selector((name)), to: nil, from: nil) {
            return
        }
        NSLog("Cadence: no Settings action responded")
    }

    @MainActor
    private static func promote() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
