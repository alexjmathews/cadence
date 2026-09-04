import SwiftUI

/// The timer window, laid out on the specification's row grid (§3.1) at a default
/// and minimum 520 × 414 pt.
///
/// Every row is allocated in every state and only its contents change — the
/// reserved event-title row, the 96 pt numerals, the 62 pt swap slot, the button
/// row, and the 68 pt calendar strip that holds its height when empty. That is the
/// whole mechanism behind "the quick durations disappear once a session starts"
/// costing no layout movement, and it is why the strip's height is real before
/// there is a calendar to put in it.
///
/// **Resizing (§3.2).** The window is resizable and the grid stretches in exactly
/// one place: the two `Spacer`s either side of the numerals block. They share any
/// extra height equally — the first carrying `topInset` as its floor, the second
/// starting from nothing — which keeps the numerals optically centred while every
/// row keeps its stated height, the strip stays pinned to the bottom, and the
/// numerals stay at 92 pt rather than becoming a fraction of the frame. Extra
/// width widens the rows' content (the rule, the strip, the button row) because
/// each row is `maxWidth: .infinity` inside the same padding column.
///
/// It renders from the same `SessionController` as the dropdown, so the two agree
/// while both are on screen, and every control calls a transition on it.
struct TimerWindow: View {
    let controller: SessionController
    let calendar: CalendarController

    private typealias Row = DesignTokens.Layout.WindowRow

    var body: some View {
        Group {
            if calendar.isDayListExpanded {
                dayList
            } else {
                timer
            }
        }
        // The content view's minimum, which is the *frame's* 520 × 414 less the
        // title bar (see `WindowGeometry`). Resizing is bounded without being
        // forbidden. It lives out here so the day list is bounded by the same box
        // the timer is and expanding it cannot resize the window.
        .frame(
            minWidth: DesignTokens.Layout.windowContentSize.width,
            maxWidth: .infinity,
            minHeight: DesignTokens.Layout.windowContentSize.height,
            maxHeight: .infinity
        )
        .background(shell(controller.status))
        .background(WindowChrome(background: shell(controller.status)))
    }

    // MARK: - Calendar

    /// What the strip is showing, derived fresh on every render from the snapshot,
    /// today's dismissals, the saved buffer and the tick. Nothing about it is stored,
    /// which is what makes a dismissal promote the next event without anything having
    /// to promote it (§4).
    private var stripContent: StripContent {
        CalendarPresentation.strip(
            snapshot: calendar.snapshot(at: controller.now),
            access: calendar.access,
            dismissed: calendar.dismissed,
            state: controller.state,
            buffer: controller.preferences.endEarlyBuffer,
            now: controller.now
        )
    }

    private var strip: some View {
        CalendarStrip(
            content: stripContent,
            start: { stripContent.row.map { startMeeting($0.id) } },
            dismiss: { stripContent.row.map { calendar.dismiss($0.id) } },
            toggleDayList: { calendar.isDayListExpanded.toggle() },
            refresh: { calendar.startRefresh() },
            connect: { Task { await calendar.connect() } }
        )
    }

    private var dayList: some View {
        DayList(
            content: CalendarPresentation.dayList(
                snapshot: calendar.snapshot(at: controller.now),
                dismissed: calendar.dismissed,
                state: controller.state,
                buffer: controller.preferences.endEarlyBuffer,
                now: controller.now
            ),
            access: calendar.access,
            start: { key in
                startMeeting(key)
                // The list is a way *into* a session, so starting one returns to the
                // clock that is now running.
                calendar.isDayListExpanded = false
            },
            dismiss: { calendar.dismiss($0) },
            restore: { calendar.restore($0) },
            refresh: { calendar.startRefresh() },
            close: { calendar.isDayListExpanded = false }
        )
    }

    /// P4, in one place for both the strip and the list: re-resolve the occurrence
    /// key against the live event store, materialise the buffered deadline, and hand
    /// the session a title and a duration rather than a pointer to an event. A key
    /// the store no longer agrees with starts nothing.
    ///
    /// The re-resolution is a calendar fetch, so it is awaited off the main actor
    /// rather than blocking the press; `meetingStart` takes its own `now` when it
    /// runs and computes the deadline from the live event start, so P4 is unaffected.
    private func startMeeting(_ key: String) {
        let buffer = controller.preferences.endEarlyBuffer
        Task {
            guard let meeting = await calendar.meetingStart(for: key, buffer: buffer)
            else { return }
            controller.startMeeting(meeting)
        }
    }

    // MARK: - Timer

    private var timer: some View {
        let status = controller.status
        let slot = WindowSwapSlot.slot(for: controller.state, at: controller.now)

        return VStack(spacing: 0) {
            // Flexible region one (§3.2). Its floor is the inset that clears the
            // traffic lights over the transparent title bar — as the content view
            // measures it, which is a title bar below the window's own top edge.
            Spacer(minLength: Row.contentTopInset)

            eventTitleRow(status)
            numeralsRow(status, isEditable: slot.offersDurationSelection)

            // Flexible region two. Zero at the default height; SwiftUI splits the
            // leftover evenly between the two spacers above their minimums, which
            // is what keeps the numerals block centred as the window grows.
            Spacer(minLength: Row.numeralsToSwapSlotInset)

            swapSlotRow(slot, status: status)
            buttonRow(status)

            // Fixed, not flexible: the transport keeps its distance from the footer
            // whatever the window's height.
            Color.clear.frame(height: Row.buttonsToStripGap)

            strip
        }
    }

    // MARK: - Shell

    /// The whole shell recolors once a session finishes, title bar included — which
    /// is what `WindowChrome` carries out of SwiftUI and into the `NSWindow`.
    private func shell(_ status: SessionStatus) -> Color {
        status == .complete ? DesignTokens.Surface.complete : DesignTokens.Surface.base
    }

    private func accent(_ status: SessionStatus) -> Color {
        status == .complete ? DesignTokens.Accent.complete : DesignTokens.Accent.base
    }

    /// Idle and paused read as plain numerals; running takes the accent and
    /// complete the mint, as the mockups draw them.
    private func numeralsColor(_ status: SessionStatus) -> Color {
        switch status {
        case .idle, .paused: DesignTokens.TextColor.primary
        case .running: DesignTokens.Accent.text
        case .complete: DesignTokens.Accent.completeText
        }
    }

    // MARK: - Event title (reserved row)

    /// Occupied only by a named session; reserved otherwise, so the numerals sit at
    /// the same height whether or not the session has a name.
    ///
    /// The title truncates rather than wraps: the window is fixed and the risk
    /// register asks for a long event name to lose its tail, never the grid.
    @ViewBuilder
    private func eventTitleRow(_ status: SessionStatus) -> some View {
        HStack(spacing: Row.eventTitleBarGap) {
            if let title = controller.state.title {
                // A mark, not a thing to read: VoiceOver would otherwise stop on an
                // unlabelled image before reaching the name beside it.
                RoundedRectangle(cornerRadius: DesignTokens.Component.eventColorBarRadius)
                    .fill(DesignTokens.Accent.event)
                    .frame(
                        width: DesignTokens.Component.eventColorBarWidth,
                        height: Row.eventTitleBarHeight
                    )
                    .accessibilityHidden(true)

                Text(title)
                    .accessibilityLabel("Session name, \(title)")
                    .font(DesignTokens.Typography.windowEventTitle)
                    .foregroundStyle(DesignTokens.TextColor.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, Row.horizontalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: Row.eventTitleHeight,
            maxHeight: Row.eventTitleHeight
        )
    }

    // MARK: - Numerals

    private func numeralsRow(_ status: SessionStatus, isEditable: Bool) -> some View {
        EditableNumerals(
            duration: controller.state.remaining(controller.now),
            color: numeralsColor(status),
            accessibilityStatus: status,
            isEditable: isEditable,
            commit: controller.selectDuration,
            start: controller.start
        )
        .padding(.top, Row.numeralsTopInset)
        .padding(.horizontal, Row.horizontalPadding)
    }

    // MARK: - Swap slot

    /// One fixed 62 pt box, three sets of contents (§3.1). Nothing outside it moves
    /// when a session starts or finishes.
    private func swapSlotRow(_ slot: WindowSwapSlot, status: SessionStatus) -> some View {
        Group {
            switch slot {
            case .durations:
                durations()
            case .progress(let statusLine):
                progressColumn(status: status) {
                    Text(statusLine)
                        .font(DesignTokens.Typography.statusLine)
                        .foregroundStyle(DesignTokens.TextColor.tertiary)
                }
            case .summary(let line):
                progressColumn(status: status) {
                    // The heading and the span read as one announcement: focus stopping
                    // twice to say "Session complete" and then a bare time range makes
                    // the second stop meaningless on its own.
                    VStack(spacing: 0) {
                        Text("Session complete")
                            .font(DesignTokens.Typography.windowButton)
                            .foregroundStyle(DesignTokens.Accent.completeText)

                        if let line {
                            Text(line)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Accent.completeCaption)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.top, Row.swapSlotTopInset)
        .padding(.horizontal, Row.horizontalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: Row.swapSlotTopInset + Row.swapSlotHeight,
            maxHeight: Row.swapSlotTopInset + Row.swapSlotHeight
        )
    }

    private func progressColumn(
        status: SessionStatus,
        @ViewBuilder caption: () -> some View
    ) -> some View {
        VStack(spacing: Row.ruleToStatusGap) {
            ProgressRule(
                progress: controller.state.progress(controller.now),
                fill: accent(status)
            )
            caption()
        }
    }

    /// Quick durations and the end-early buffer. Present only while idle: §5's
    /// third guard makes duration selection legal nowhere else, and the swap slot
    /// is the mechanism that enforces it in the window rather than merely refusing
    /// the press.
    private func durations() -> some View {
        VStack(spacing: Row.presetsToBufferGap) {
            HStack(spacing: Row.presetChipGap) {
                ForEach(controller.presets) { preset in
                    // The chip shows `45 min`; VoiceOver says what pressing it does.
                    Button(preset.shortTitle) { controller.select(preset) }
                        .buttonStyle(PresetChipStyle())
                        .accessibilityLabel("Set duration to \(preset.title)")
                }
            }

            HStack(spacing: Row.bufferChipGap) {
                Text("end early by")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.TextColor.quaternary)

                // A stored value the chips do not offer lights up nothing rather
                // than the nearest thing, which is what `selected(for:)` decides.
                let selected = BufferOption.selected(for: controller.preferences.endEarlyBuffer)
                ForEach(BufferOption.all) { option in
                    BufferChip(option: option, isSelected: option == selected) {
                        controller.setBuffer(option.seconds)
                    }
                }
            }
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private func buttonRow(_ status: SessionStatus) -> some View {
        HStack(spacing: Row.buttonGap) {
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
        .padding(.top, Row.buttonsTopInset)
        .padding(.horizontal, Row.horizontalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: Row.buttonsTopInset + Row.buttonsHeight,
            maxHeight: Row.buttonsTopInset + Row.buttonsHeight
        )
    }

    private func primary(
        _ title: String,
        status: SessionStatus,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(
                WindowPrimaryButtonStyle(
                    fill: accent(status),
                    label: status == .complete
                        ? DesignTokens.TextColor.onComplete
                        : DesignTokens.TextColor.onAccent
                )
            )
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(WindowSecondaryButtonStyle())
    }
}

// MARK: - Numerals

/// The 96 pt numerals: two digits-only fields with the colon drawn between them as
/// chrome (D9).
///
/// The colon is a `Text`, not a character in a field, so it cannot be deleted,
/// duplicated, or typed into. Each field refuses anything that is not a digit at the
/// **responder** — see `NumeralField`, which is why the halves are `NSTextField`s —
/// so there is no malformed state to validate and nothing to explain. Minutes take
/// three digits; seconds are held to `0…59` by the same refusal.
///
/// `Tab` and `Shift-Tab` swap the two fields. `Return` commits and starts the
/// session from either. The commit happens **on blur or `Return`** and never on an
/// empty field (D9): per-keystroke commits walk `plannedDuration` through every
/// intermediate value, so clearing minutes to retype them would put a nine-second
/// plan in the App Group and reload every widget timeline on the way past. When the
/// session leaves `idle` the fields are replaced by plain text, because §5's third
/// guard makes the commit illegal from that moment on.
///
/// **The colon sits on the window's centre line** (§3.2). The two halves are
/// equal-width columns — minutes trailing-aligned, seconds leading-aligned — so a
/// third minute digit widens the left column without sliding the clock sideways.
/// Tracking is added after the final glyph as well as between glyphs, so the minutes
/// column negates it as trailing padding to put its last digit *on* the column edge.
///
/// Internal rather than private so `SpokenLabelTests` can build the real row and read the
/// accessibility label off it. `SpokenText` being well tested says nothing about whether
/// any view calls it — reverting this row's label to the padded `05:00` was measured
/// leaving the whole suite green.
struct EditableNumerals: View {
    let duration: TimeInterval
    let color: Color
    /// The status the clock is announced as, which is not derivable from `isEditable`:
    /// `idle` and `complete` both make the numerals non-editable (§5's third guard
    /// permits selection only in `idle`, and the swap slot enforces it), and the two say
    /// very different things.
    let accessibilityStatus: SessionStatus
    let isEditable: Bool
    let commit: (TimeInterval) -> Void
    let start: () -> Void

    enum Half { case minutes, seconds }

    /// The live text of both halves plus which one holds the caret, in one
    /// reference so a delegate callback composing the pair always reads the
    /// keystroke that has just landed rather than the previous render's copy.
    @State private var draft = NumeralDraft()

    private typealias Row = DesignTokens.Layout.WindowRow
    private typealias TypeToken = DesignTokens.Typography

    var body: some View {
        HStack(spacing: 0) {
            if isEditable {
                editable(.minutes)
                colon
                editable(.seconds)
            } else {
                rendered(ClockFormatter.minutesText(duration))
                colon
                rendered(ClockFormatter.secondsText(duration), half: .seconds)
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: Row.numeralsHeight, maxHeight: Row.numeralsHeight)
        // The clock is the one thing every surface exists to show (D10), so it is one
        // accessibility element rather than three — two halves and a colon read as
        // "zero five", "colon", "zero zero" otherwise. It is announced in words, since
        // the two-digit padding is a fact about monospaced glyphs and not about the
        // time. While editable the fields keep their own focus and values, so the
        // combined element is only claimed when they are not controls.
        .accessibilityElement(children: isEditable ? .contain : .ignore)
        .accessibilityLabel(SpokenText.clockLabel(for: accessibilityStatus))
        .accessibilityValue(isEditable ? "" : SpokenText.duration(duration))
        // The fields mirror the plan whenever they are not the thing changing it:
        // a preset chip, a widget-driven reset, or the window opening.
        .onChange(of: duration, initial: true) { _, _ in syncFromPlan() }
        .onChange(of: isEditable, initial: true) { _, editable in
            if !editable { draft.focus = nil }
            syncFromPlan()
        }
    }

    /// Immovable chrome. Non-focusable and non-selectable by construction — it is a
    /// label, not a character anything can reach. It carries no tracking, so its ink
    /// is centred in its own advance and therefore on the window's centre line.
    private var colon: some View {
        Text(":")
            .font(TypeToken.windowNumerals)
            .monospacedDigit()
    }

    /// A half in its non-editable form, on the same symmetric column the editable
    /// one uses, so nothing moves sideways when a session starts.
    private func rendered(_ text: String, half: Half = .minutes) -> some View {
        column(half) {
            Text(text)
                .font(TypeToken.windowNumerals)
                .tracking(TypeToken.windowNumeralsTracking)
                .monospacedDigit()
        }
    }

    private func editable(_ half: Half) -> some View {
        column(half) {
            NumeralField(
                text: half == .minutes ? $draft.minutes : $draft.seconds,
                field: half == .minutes ? .minutes : .seconds,
                alignment: half == .minutes ? .right : .left,
                color: color,
                isFocused: draft.focus == half,
                onFocus: { draft.focus = half },
                onTab: { draft.focus = half == .minutes ? .seconds : .minutes },
                onCommit: { commitDraft() },
                onReturn: start
            )
        }
    }

    /// One of the two equal-width symmetric columns (§3.2).
    private func column(_ half: Half, @ViewBuilder content: () -> some View) -> some View {
        content()
            // Negating the tracking pulls the trailing-aligned minutes' last digit
            // onto the column edge; the leading-aligned seconds already start on
            // theirs.
            .padding(.trailing, half == .minutes ? TypeToken.windowNumeralsTracking : 0)
            .frame(
                minWidth: Row.numeralFieldMinimumWidth,
                maxWidth: .infinity,
                alignment: half == .minutes ? .trailing : .leading
            )
    }

    /// Blur and `Return` land here. An empty half commits nothing and the numerals
    /// simply fall back to the plan they still hold.
    private func commitDraft() {
        if let duration = DurationInput.commitDuration(
            minutes: draft.minutes,
            seconds: draft.seconds
        ) {
            commit(duration)
        }
        syncFromPlan()
    }

    private func syncFromPlan() {
        let minutesText = DurationInput.minutesText(for: duration)
        let secondsText = DurationInput.secondsText(for: duration)
        // Only the half that is not being typed into is rewritten, so padding never
        // fights the caret.
        if draft.focus != .minutes, draft.minutes != minutesText { draft.minutes = minutesText }
        if draft.focus != .seconds, draft.seconds != secondsText { draft.seconds = secondsText }
    }
}

/// The editing draft the two halves share. A reference rather than two `@State`
/// strings because the responder callbacks that compose the pair run between
/// renders: a captured copy of the *previous* body's value would commit the
/// keystroke before last.
@MainActor
@Observable
private final class NumeralDraft {
    var minutes = ""
    var seconds = ""
    var focus: EditableNumerals.Half?
}

// MARK: - Progress

/// The window's 5 pt rule, full width of the content column.
///
/// **Reduce Motion has nothing to suppress here, and that is by construction.** The
/// rule carries no `.animation` and no `withAnimation`: its width is a pure function of
/// `progress(now)`, and `now` advances once a second from the display ticker (D1). So
/// the fill steps rather than sliding, which is already the behaviour Reduce Motion
/// asks for — there is no transition to shorten and no interpolation to disable. An
/// implicit animation added here later would be a motion regression that no
/// `accessibilityReduceMotion` read in this file would catch, so the discipline is
/// "the rule does not animate" rather than "the rule animates conditionally".
///
/// It is announced as a value with no hint, because it is a rule and not a control:
/// there is nothing to do to it.
private struct ProgressRule: View {
    let progress: Double
    let fill: Color

    var body: some View {
        let radius = DesignTokens.Component.progressRuleRadius

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: radius)
                .fill(DesignTokens.Surface.progressTrack)

            GeometryReader { proxy in
                let width = proxy.size.width * progress
                // Below its own corner diameter the fill collapses into the track's
                // left cap and reads as progress that has not happened.
                if width >= DesignTokens.Component.progressRuleHeight {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(fill)
                        .frame(width: width)
                }
            }
        }
        .frame(height: DesignTokens.Component.progressRuleHeight)
        .accessibilityElement()
        .accessibilityLabel("Session progress")
        .accessibilityValue(SpokenText.progress(progress))
    }
}

// MARK: - Button styles

/// One end-early chip, whose visible label is `off` / `1m` / `2m` / `3m`.
///
/// Its own view rather than three modifiers inside a `ForEach`, and internal rather than
/// private, for one reason: `SpokenLabelTests` can build a chip and read the spoken label
/// off it, which a closure inside a `ForEach` does not expose. Deleting
/// `SpokenText.buffer` here was measured leaving the whole suite green, and `2m` read out
/// as "two em" is the case the file exists for.
struct BufferChip: View {
    let option: BufferOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(option.label, action: action)
            .buttonStyle(BufferChipStyle(isSelected: isSelected))
            .accessibilityLabel(SpokenText.buffer(option.seconds))
            // The chip row is a single choice, so the selected one has to announce
            // itself as chosen rather than merely look chosen.
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct WindowPrimaryButtonStyle: ButtonStyle {
    let fill: Color
    let label: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.windowButton)
            .foregroundStyle(label)
            .padding(DesignTokens.Component.primaryButtonPadding)
            .background(
                fill,
                in: .rect(cornerRadius: DesignTokens.Component.primaryButtonRadius)
            )
            .opacity(configuration.isPressed ? DesignTokens.Component.pressedOpacity : 1)
    }
}

private struct WindowSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Component.secondaryButtonRadius)

        return configuration.label
            .font(DesignTokens.Typography.windowButton)
            .foregroundStyle(DesignTokens.TextColor.primary)
            .padding(DesignTokens.Component.secondaryButtonPadding)
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

private struct PresetChipStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Component.presetChipRadius)

        return configuration.label
            .font(DesignTokens.Typography.body)
            .foregroundStyle(DesignTokens.TextColor.primary)
            .padding(DesignTokens.Component.presetChipPadding)
            .background(
                isHovering || configuration.isPressed
                    ? DesignTokens.Surface.fillHover
                    : DesignTokens.Surface.fillSubtle,
                in: shape
            )
            .overlay {
                shape.strokeBorder(
                    DesignTokens.Surface.hairline,
                    lineWidth: DesignTokens.Component.hairlineWidth
                )
            }
            .opacity(configuration.isPressed ? DesignTokens.Component.pressedOpacity : 1)
            .onHover { isHovering = $0 }
    }
}

private struct BufferChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.chipMeta)
            .monospacedDigit()
            .foregroundStyle(
                isSelected ? DesignTokens.Accent.text : DesignTokens.TextColor.tertiary
            )
            .padding(DesignTokens.Component.bufferChipPadding)
            .background(
                isSelected ? DesignTokens.Surface.fillAccentSelected : .clear,
                in: .rect(cornerRadius: DesignTokens.Component.bufferChipRadius)
            )
            .opacity(configuration.isPressed ? DesignTokens.Component.pressedOpacity : 1)
    }
}

// MARK: - Window chrome

/// Carries the shell color out of SwiftUI and onto the `NSWindow`.
///
/// The visual specification asks for the *whole* shell to recolor on completion,
/// "title bar included", and a SwiftUI background cannot reach the title bar on its
/// own. Three things together do: a full-size content view with a transparent title
/// bar, so the content's own background paints the strip behind the traffic lights;
/// the window's `backgroundColor`, so the rounded corners and any resize seam match
/// rather than showing system grey; and a pinned dark appearance, because the title
/// bar material and the window buttons otherwise follow the system theme and put a
/// light bar over a near-black window.
private struct WindowChrome: NSViewRepresentable {
    var background: Color

    func makeNSView(context: Context) -> NSView {
        ChromeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ChromeView)?.background = NSColor(background)
    }

    /// The window is not available until the view joins one, and the shell color
    /// changes after that, so both paths re-apply.
    private final class ChromeView: NSView {
        var background: NSColor = .clear {
            didSet { if background != oldValue { apply() } }
        }

        private var hasConfiguredGeometry = false
        private var isObservingKey = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureGeometry()
            apply()
            observeKey()
            // SwiftUI installs the first text field as first responder *after* this
            // runs, so clearing it here alone was a race the window kept losing.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.clearFirstResponder() }
            }
        }

        /// The size criterion — see `WindowGeometry` for why the grid is laid out to
        /// a content size rather than to §3's frame.
        ///
        /// Once, per window. Re-asserting on every shell recolor would snap a window
        /// the user had dragged larger back to its default the moment a session
        /// finished.
        private func configureGeometry() {
            guard !hasConfiguredGeometry, let window else { return }
            hasConfiguredGeometry = true
            WindowGeometry.apply(to: window)
        }

        private func apply() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = background
            clearFirstResponder()
        }

        /// SwiftUI installs the window's first text field as first responder *after*
        /// the view has moved to the window, so clearing it here alone was a race the
        /// window kept losing: it opened with a caret in the minutes field and ate
        /// arbitrary keystrokes into the duration. `NumeralTextField` refuses first
        /// responder until a click or a `Tab` offers it, which is the actual fix;
        /// this is the belt to that pair of braces, and it runs on the notification
        /// that fires after the responder chain has settled.
        private func observeKey() {
            guard !isObservingKey, let window else { return }
            isObservingKey = true
            // The selector form, whose observer reference is zeroing-weak, so there
            // is nothing to unregister when the view goes away.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
        }

        @objc private func windowDidBecomeKey() {
            clearFirstResponder()
        }

        /// SwiftUI installs the window's first text field as first responder when the
        /// window opens, which is how an untouched window came to hold a 92 pt caret
        /// and eat arbitrary keystrokes into the duration. So the caret is cleared
        /// unless the field says the user asked for it — a click, a `Tab` from the
        /// other half, or VoiceOver. Clearing unconditionally would take the caret
        /// away mid-edit whenever the window was reactivated.
        private func clearFirstResponder() {
            guard let window,
                  let editor = window.firstResponder as? NSTextView
            else { return }
            if editor.owningNumeralField?.isUserFocused == true { return }
            window.makeFirstResponder(nil)
        }
    }
}

// MARK: - Window geometry

/// Where the window's frame size is settled, and why it is not the number the grid
/// is laid out to.
///
/// `.windowStyle(.hiddenTitleBar)` makes the title bar transparent but does **not**
/// remove it from the frame: the SwiftUI content view is the frame less
/// `windowTitlebarHeight`. Laying the grid out to §3's 414 pt therefore shipped a
/// 446 pt window — and 446 became the resize floor too — with every row sitting a
/// title bar lower against the top edge than the mockup draws it. So the grid is laid
/// out to `windowContentSize` and the *frame* comes out at 520 × 414.
///
/// Inserting `.fullSizeContentView` instead does not work: SwiftUI then reserves the
/// title bar as a safe area *inside* the content view and adds it back to the size it
/// asks the window for, which is 446 again by another route.
@MainActor
enum WindowGeometry {
    /// The title bar the running system actually adds, which the token claims is
    /// `windowTitlebarHeight`.
    static func titlebarHeight(of window: NSWindow) -> CGFloat {
        window.frame.height - window.contentRect(forFrameRect: window.frame).height
    }

    static func apply(to window: NSWindow) {
        // SwiftUI's `.defaultSize` and the content's own `minHeight` already compose
        // to the specified frame, so there is nothing to correct on a system whose
        // title bar is the height the token says. On one where it is not, the frame
        // is asserted rather than left a few points off the specification.
        let measured = titlebarHeight(of: window)
        guard measured != DesignTokens.Layout.windowTitlebarHeight else { return }

        window.setContentSize(
            CGSize(
                width: DesignTokens.Layout.windowSize.width,
                height: DesignTokens.Layout.windowSize.height - measured
            )
        )
    }
}

private extension NSTextView {
    /// The numeral field this text view is the field editor for, if any. A field
    /// editor is a shared view AppKit parks inside the control being edited, so the
    /// owner is up the view hierarchy rather than on the delegate.
    var owningNumeralField: NumeralTextField? {
        var view: NSView? = superview
        while let current = view {
            if let field = current as? NumeralTextField { return field }
            view = current.superview
        }
        return nil
    }
}
