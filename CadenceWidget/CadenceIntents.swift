import AppIntents
import Foundation
import WidgetKit

// See `CadenceWidgetViews.swift`: the views the test bundle renders reach this intent
// through `Button(intent:)`, so it compiles there too and finds `WidgetAction` in the
// host app's module rather than its own.
#if CADENCE_TESTS
@testable import Cadence
#endif

// MARK: - Completion notifications: the §5 risk row, investigated
//
// The risk table's row "a widget extension may not be permitted to post local
// notifications" was a Stage 4 *investigation*, and this is its result. Nothing here
// is implemented — scheduling is Stage 5 — but the shape Stage 5 has to build is now
// a measurement rather than a guess, and it is **not** the shape D3 assumes.
//
// ## Method
//
// A probe binary was signed with this extension's own identity — bundle id
// `com.alexmathews.cadence.widget`, `CFBundlePackageType` `XPC!`, the
// `com.apple.widgetkit-extension` `NSExtension` point, the App Sandbox and the App
// Group — and run from the `.appex` inside a LaunchServices-registered
// `Cadence.app`. macOS 26.
//
// One trap is worth recording, because it wasted the first three attempts and will
// waste anyone else's: `UNUserNotificationCenter.current()` throws
// `NSInternalInconsistencyException — bundleProxyForCurrentProcess is nil` for a
// process whose bundle LaunchServices does not know, and `lsregister` on a scratch
// path is not enough. That exception is an artefact of *where the bundle lives*, not
// evidence about extensions; a copy of the same bundle at the registered build-product
// path resolves fine. Do not read it as "extensions cannot post notifications".
//
// ## What was measured
//
// 1. **An extension can schedule.** `UNUserNotificationCenter.current()` returns a
//    centre, `getNotificationSettings` reports `.authorized` (raw 2) *without the
//    extension ever prompting* — the grant follows the containing app — and
//    `add(UNNotificationRequest)` returns `error == nil` with the request appearing
//    in `getPendingNotificationRequests`. So the pessimistic branch of the risk row
//    does not happen: a widget-initiated start *can* arm its own alarm.
//
// 2. **It survives the extension being torn down.** A request scheduled 20 s out
//    fired with the extension process long gone, and afterwards read back as
//    `pending = 0, delivered = 1`. Nothing has to stay awake, which is exactly D3's
//    premise.
//
// 3. **It does not attribute to the app, and this is the finding that matters.**
//    The two bundle identifiers get two separate notification stores. Measured:
//
//    - the app scheduled `cadence.completion`; its own `getPendingNotificationRequests`
//      returned 1;
//    - the extension called `removePendingNotificationRequests(withIdentifiers:)` for
//      that identifier and reported 0 pending in its store;
//    - the app re-checked and **still had its request**, unharmed;
//    - only the app could cancel the app's request.
//
//    Symmetrically, a request scheduled by the extension is invisible to the app:
//    after the extension's notification had fired, the app read
//    `pending = 0, delivered = 0`.
//
// ## What that means for Stage 5
//
// **D3's fallback as written is not implementable.** D3 says scheduling belongs to
// the app and "intents only cancel", with the app reconciling pending requests when it
// next observes the container. Point 3 kills both halves: an intent *cannot* cancel
// what the app scheduled, and the app *cannot* enumerate or reconcile what an intent
// scheduled. Neither process can see, let alone clean up, the other's requests. A
// `pause` pressed on the widget would leave the app's completion alarm armed and fire
// it at a session that is not running — which is worse than the missing alarm the row
// was worried about.
//
// And the "app reconciles later" escape does not cover the case it exists for. With
// the app quit for the whole session — the ordinary case for a widget, since D2's
// entire point is that these controls work without it — there is no app to schedule
// at press time and no app to reconcile before the deadline passes. Today that alarm
// is simply lost: nothing in the tree schedules anything, and `AppDelegate.swift:10`
// is a delegate assignment.
//
// **So each writer must own its own alarm, in its own store.** The shape the
// measurement supports:
//
// - whichever process performs a transition also schedules or cancels, in its own
//   notification store, under one stable identifier;
// - both processes therefore need the write path to reach a scheduler, which means
//   the scheduler belongs in `Shared/` beside `WidgetActions`, taking the store as an
//   argument the way the transitions take `now`;
// - the duplicate-alarm case is real and has to be handled deliberately: press
//   `start` on the widget, then `pause` in the app, and the widget's request is still
//   armed and cannot be reached. The honest mitigations are to have whichever process
//   *is* awake at fire time suppress a notification that disagrees with the container
//   (`UNUserNotificationCenterDelegate` already exists in `AppDelegate` for exactly
//   this), and to accept that a stale alarm from a quit process is a possible
//   duplicate rather than a wrong time — `endsAt` is stored, so a fired alarm is never
//   *early*.
//
// The one thing Stage 5 should not do is spend the stage rediscovering that
// `removePendingNotificationRequests` across the boundary silently succeeds and
// changes nothing. It does. It was measured.

/// The widget's write side (D2). One intent, invoked by one control, running in the
/// widget extension's own process: the App Group is mutated directly rather than
/// round-tripped through the app, so every control works with the app quit, and
/// `openAppWhenRun` is `false` so none of them ever brings it to the front.
///
/// **Why one parameterised intent rather than seven types.** §4 asks that every
/// widget control be a single App Intent, which it is: a press performs exactly one
/// intent and one transition, with no chaining and no configuration step. What §4
/// does not ask for is seven near-identical declarations, and the Shortcuts surface
/// that would justify them — user-facing, individually-titled actions — is Stage 5's
/// `CadenceShortcuts` over the same `WidgetActions` entry point. Splitting this type
/// then is a rename; splitting it now would be seven copies of one `perform`.
///
/// The parameters are the resolved arguments the *control* already knew, never a
/// snapshot of the session: `perform` re-reads the container before transitioning, so
/// a press from a timeline generated an hour ago is judged against the session the
/// user is looking at.
struct CadenceActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Cadence Session Action"
    static let description = IntentDescription(
        "Starts, pauses, resumes, resets or extends the current Cadence session."
    )

    /// The whole point: the container is the surface, not the app (D2).
    static let openAppWhenRun = false

    /// Which transition, as `WidgetAction.Kind`'s raw value.
    @Parameter(title: "Action")
    var kind: String

    /// Seconds, for `startDuration`. Zero otherwise.
    @Parameter(title: "Duration")
    var duration: Double

    /// The occurrence key, for `startMeeting`. Empty otherwise.
    @Parameter(title: "Event")
    var eventKey: String

    init() {
        kind = WidgetAction.Kind.start.rawValue
        duration = 0
        eventKey = ""
    }

    init(_ action: WidgetAction) {
        self.init()
        kind = action.kind.rawValue
        switch action {
        case .startDuration(let seconds): duration = seconds
        case .startMeeting(let key): eventKey = key
        default: break
        }
    }

    @discardableResult
    func perform() async throws -> some IntentResult {
        guard let action = WidgetAction(
            kind: kind,
            duration: duration,
            eventKey: eventKey
        ) else {
            // A parameter set this build does not recognise. Doing nothing is the
            // only safe answer: guessing a transition from a malformed request is how
            // a widget comes to start a session nobody asked for.
            return .result()
        }

        // `.shared` is passed rather than defaulted: the alarm is armed in *this*
        // process's notification store (D3), and `perform`'s default is deliberately
        // no scheduler so that a caller which is not a real writer cannot acquire one
        // by omission.
        if !WidgetActions.perform(action, scheduler: .shared).changed {
            // `SharedStore` reloads every timeline on a successful write, so the
            // accepted path is already covered and reloading again would be two
            // reloads for one press. A press that a guard refused writes nothing —
            // and that press is exactly the one whose timeline was stale, so it is
            // the one that most needs redrawing, and the only one that needs this.
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result()
    }
}
