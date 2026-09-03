import AppIntents
import Foundation
import WidgetKit

/// The Shortcuts, Spotlight and Siri surface, over the same transitions every other
/// surface uses.
///
/// **Why these are separate types when the widget has one parameterised intent.** The
/// widget's `CadenceActionIntent` is invoked by a control that already knows which
/// transition it means, so a `kind` parameter costs nothing and saves seven near-copies
/// of one `perform`. Shortcuts is the opposite case: the intent *is* the user interface.
/// A single "Cadence Session Action" taking a raw string would put `WidgetAction.Kind`'s
/// spelling in front of the user and make the Shortcuts editor a place to mistype
/// `resume`. Individually-titled actions are what the surface is for.
///
/// They are thin by construction — each one names an action and hands it to
/// `WidgetActions.perform`, which is the same entry point the widget's intents and the
/// `cadence://` handler use. So a Siri phrase, a Raycast command and a widget button
/// cannot produce different records: all three end in the same pure transition against
/// the same container.
///
/// These live in the app rather than the extension so that a Shortcut running while
/// Cadence is quit launches the app it names. `openAppWhenRun` is `false` on all of
/// them, so the launch is silent and nothing is brought to the front — the same
/// property D2 asks of the widget and `open -g` gives the URL scheme.

// MARK: - Shared behaviour

/// One `perform` for all six, so "what a Shortcut does" is one piece of code.
///
/// Illegal requests are silent no-ops, which is the same contract every other surface
/// has: `SessionTransitions`' guards reject by returning their input, so asking Siri to
/// pause an idle session costs a container read and changes nothing. Reporting an error
/// instead would make a Shortcut fail for a state the user can see perfectly well.
private func runCadence(_ action: WidgetAction) -> some IntentResult {
    // `.shared` explicitly: this process performed the transition, so this process owns
    // the completion alarm (D3).
    if !WidgetActions.perform(action, scheduler: .shared).changed {
        // A successful write reloads every timeline from inside `SharedStore`. A press a
        // guard refused writes nothing — and that is exactly the case where a widget's
        // timeline may be the stale thing that offered the illegal action, so it is the
        // one that needs redrawing.
        WidgetCenter.shared.reloadAllTimelines()
    }
    return .result()
}

// MARK: - Intents

struct StartSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Session"
    static let description = IntentDescription(
        "Starts a Cadence session using the duration you last chose."
    )
    static let openAppWhenRun = false

    @discardableResult
    func perform() async throws -> some IntentResult { runCadence(.start) }
}

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Timer"
    static let description = IntentDescription("Starts a Cadence session of a given length.")
    static let openAppWhenRun = false

    /// Minutes, bounded by what the surfaces can draw rather than by taste: the window's
    /// numerals are a three-digit minutes field beside a two-digit seconds field and the
    /// countdown never rolls over into hours (D9), so `999` is the longest session the
    /// product can express. The bound is declared here so Shortcuts refuses out-of-range
    /// input in its own editor instead of the app silently doing nothing.
    ///
    /// The literal is `999` and not `ClockFormatter.maximumMinutes` because `@Parameter`
    /// requires a compile-time constant. `CadenceURLTests` asserts the two agree, so the
    /// duplication cannot drift silently.
    @Parameter(title: "Minutes", default: 25, inclusiveRange: (1, 999))
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute Cadence session")
    }

    @discardableResult
    func perform() async throws -> some IntentResult {
        runCadence(.startDuration(TimeInterval(minutes) * 60))
    }
}

struct PauseSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Session"
    static let description = IntentDescription("Pauses the running Cadence session.")
    static let openAppWhenRun = false

    @discardableResult
    func perform() async throws -> some IntentResult { runCadence(.pause) }
}

struct ResumeSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Session"
    static let description = IntentDescription("Resumes the paused Cadence session.")
    static let openAppWhenRun = false

    @discardableResult
    func perform() async throws -> some IntentResult { runCadence(.resume) }
}

struct ResetSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Session"
    static let description = IntentDescription(
        "Clears the current Cadence session, keeping its duration and name."
    )
    static let openAppWhenRun = false

    @discardableResult
    func perform() async throws -> some IntentResult { runCadence(.reset) }
}

struct ExtendSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Five Minutes"
    static let description = IntentDescription(
        "Adds five minutes to a Cadence session that has just finished."
    )
    static let openAppWhenRun = false

    @discardableResult
    func perform() async throws -> some IntentResult { runCadence(.extend) }
}

// MARK: - Provider

/// What Siri and Spotlight will match, and what appears in the Shortcuts gallery.
///
/// Every phrase carries `\(.applicationName)` because App Intents requires it, and the
/// alternates are the ways the transitions are actually spoken — "stop" for pause is the
/// one worth having, since a user who says "stop my timer" means pause far more often
/// than they mean reset, and reset is spelled with its own verb.
struct CadenceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: [
                "Start a session in \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Start Session",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start a timer in \(.applicationName)",
                "Set a \(.applicationName) timer",
            ],
            shortTitle: "Start Timer",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: PauseSessionIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Pause my \(.applicationName) session",
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeSessionIntent(),
            phrases: [
                "Resume \(.applicationName)",
                "Resume my \(.applicationName) session",
            ],
            shortTitle: "Resume",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: ResetSessionIntent(),
            phrases: [
                "Reset \(.applicationName)",
                "Reset my \(.applicationName) session",
            ],
            shortTitle: "Reset",
            systemImageName: "arrow.counterclockwise"
        )
        AppShortcut(
            intent: ExtendSessionIntent(),
            phrases: [
                "Add five minutes in \(.applicationName)",
                "Extend my \(.applicationName) session",
            ],
            shortTitle: "Add Five Minutes",
            systemImageName: "plus"
        )
    }
}
