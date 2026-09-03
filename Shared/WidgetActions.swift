import Foundation

/// The transitions a widget control can ask for, named as the control names them.
///
/// This is the whole vocabulary of the widget's write side. It exists as a value
/// rather than as a set of closures so that "what a press does" is decided by a
/// pure function (`WidgetActions.next`) that the tests can drive without a
/// container, and so that the intent types in the extension are thin adapters
/// around one code path rather than seven near-copies of it.
enum WidgetAction: Equatable, Sendable {
    /// `Start 25 min` and `Start another` — the stored plan, unchanged.
    case start
    /// A suggestion row: `45 minutes`, `To 2:30`. The duration is already resolved
    /// by the caller, because the row's label promised it (D7).
    case startDuration(TimeInterval)
    /// The medium's meeting row. The buffer is *not* an argument: it is read from
    /// `preferences` at press time (§2.2, P4), which is what makes a meeting timer
    /// started from the widget end as early as one started from the window.
    case startMeeting(eventKey: String)
    case pause
    case resume
    case reset
    case extend
}

/// The widget's write path (D2): an intent mutates `sessionState` in the extension's
/// own process, so the controls work with the app quit and never foreground it.
///
/// Two properties make that safe, and both live here rather than in the intents:
///
/// - **Every press transitions from the container, never from the timeline.** A
///   widget's entry is a snapshot of the session as it was when WidgetKit last asked
///   for a timeline, which may be minutes or hours old and may predate a write by the
///   app. `perform` re-reads immediately before transitioning — the same discipline
///   `SessionController.apply` follows on the other side of the container — so a
///   stale tap is judged against the state the user is actually looking at rather
///   than clobbering a newer record with an older one.
/// - **Illegal requests are no-ops that return the reconciled state.** A snapshot
///   timeline can legitimately offer `Pause` on a session that has since completed.
///   `SessionTransitions` guards reject by returning their input, so the press costs
///   a write that changes nothing rather than crashing an extension.
enum WidgetActions {

    /// What the container should hold after `action`, as a pure function of what it
    /// holds now. Nothing here reads a clock or a store.
    ///
    /// `snapshot` and `preferences` are arguments for the same reason the transitions
    /// take `now`: the app and the extension must compute identical results from
    /// identical inputs, and a function that fetched its own would be two functions.
    static func next(
        _ action: WidgetAction,
        state: SessionState,
        snapshot: CalendarSnapshot? = nil,
        preferences: Preferences = Preferences(),
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SessionState {
        switch action {
        case .start:
            // `start` is legal from `idle` and from `complete`, which is the
            // `Start another` edge; the guard inside it is what makes the two
            // controls one action.
            return SessionTransitions.start(state, duration: state.plannedDuration, now: now)

        case .startDuration(let duration):
            return SessionTransitions.start(state, duration: duration, now: now)

        case .startMeeting(let key):
            guard let meeting = meetingStart(
                key: key,
                snapshot: snapshot,
                buffer: preferences.endEarlyBuffer,
                now: now,
                calendar: calendar
            ) else {
                // The occurrence is gone from the snapshot, the day has rolled over,
                // or the buffer has eaten what was left. Starting the stored plan
                // instead would start a session the row did not offer.
                return SessionTransitions.reconciled(state, now: now)
            }
            return SessionTransitions.start(
                state,
                duration: meeting.duration,
                title: meeting.title,
                linkedEventKey: meeting.key,
                now: now
            )

        case .pause:
            return SessionTransitions.pause(state, now: now)
        case .resume:
            return SessionTransitions.resume(state, now: now)
        case .reset:
            return SessionTransitions.reset(state, now: now)
        case .extend:
            return SessionTransitions.extend(state, now: now)
        }
    }

    /// What a press did: the state the container now holds, and whether the press
    /// changed it. The caller needs both — the state to redraw against, and `changed`
    /// to know whether `SharedStore`'s own write-side timeline reload has already
    /// happened or whether it has to ask for one itself.
    struct Outcome: Equatable, Sendable {
        let state: SessionState
        /// False when a guard refused the press or reconciliation found nothing to
        /// fold in. Nothing was written, so nothing reloaded.
        let changed: Bool
    }

    /// Re-reads the container, transitions, and writes back. The return value is what
    /// the container now holds, so a caller can reload its timeline against the truth
    /// rather than against what it hoped for.
    ///
    /// A refused write leaves the container alone and returns the base, on the same
    /// terms `SessionController.apply` uses: an unwritten transition simply did not
    /// happen, and a widget that redrew as though it had would be the one surface
    /// disagreeing with the other three.
    ///
    /// `now` defaults to the wall clock — the one clock read in `Shared/`, and a
    /// deliberate exception rather than a lapse. The purity rule exists so that the
    /// app and the extension compute identical results from identical inputs, which
    /// is a property of the *transitions*; `next` above holds it, and every test
    /// drives that. `perform` is the impure edge on the other side of it: it already
    /// touches the store, and an intent firing from a widget press has no `now` to
    /// pass but the instant of the press. Callers that need determinism inject it,
    /// and all of them do.
    /// `scheduler` is the extension's own notification store (D3). It is a parameter
    /// on the same terms `store` is: the app and the extension run this one code path,
    /// and each arms or cancels in the store its own process owns, because Stage 4
    /// measured that neither can reach the other's.
    ///
    /// It defaults to `nil` rather than to `.shared`, and the intent passes `.shared`
    /// explicitly. A test that forgot the argument would otherwise arm a real alarm
    /// and raise a real authorization prompt on the machine running the suite, which
    /// is a side effect no unit test should be able to acquire by omission.
    @discardableResult
    static func perform(
        _ action: WidgetAction,
        store: SharedStore = .shared,
        scheduler: CompletionScheduler? = nil,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Outcome {
        let base = store.loadSessionState(now: now)
        let next = next(
            action,
            state: base,
            snapshot: store.loadCalendarSnapshot(now: now, calendar: calendar),
            preferences: store.loadPreferences(),
            now: now,
            calendar: calendar
        )
        guard next != base else {
            // A guard rejected the press, or reconciliation found nothing to fold in.
            // Either way there is nothing to write, and writing anyway would reload
            // every timeline on the machine for a press that changed nothing.
            return Outcome(state: base, changed: false)
        }
        guard store.save(next) else {
            NSLog("Cadence: widget action dropped — the container refused the write")
            return Outcome(state: base, changed: false)
        }
        // This press is a write, so it owns the alarm it implies — armed here, in this
        // process's store, whether or not the app is running. That is the case D3 was
        // amended for: with the app quit for the whole session, which D2 makes the
        // ordinary widget case, there is nobody else to arm it and nobody else to
        // notice it was never armed.
        //
        // A press a guard refused returns above without reaching this: nothing was
        // written, so nothing about the alarm changed either.
        scheduler?.reconcile(with: next, now: now)
        return Outcome(state: next, changed: true)
    }

    // MARK: - Meeting start

    /// A meeting-linked start as the *extension* can resolve it.
    ///
    /// **The widget starts from the snapshot's stored start time, and this is a
    /// deliberate weakening of §2.3.** The data model calls the snapshot "display and
    /// identity data, not authority" and asks that an occurrence key be re-resolved
    /// against the live event store before a deadline is computed. The widget
    /// extension cannot do that: it is sandboxed, it holds no EventKit entitlement,
    /// and asking for one would move the TCC gate from the app the user granted it to
    /// a process they never see. The alternatives were worse — launching the app to
    /// re-resolve violates D2's "never foreground it", and refusing the row entirely
    /// deletes a story §7 puts in the widget column.
    ///
    /// The risk that buys: if the event was moved or cancelled after the app last
    /// wrote the snapshot, the widget starts a timer against a start time that no
    /// longer exists. It is bounded by three things. The snapshot is day-scoped and
    /// discarded on read once stale (§3), so the error can never be older than today.
    /// The app rewrites it on `EKEventStoreChanged`, day change, clock change and
    /// activation, so the window in which it is wrong is the window in which the app
    /// has not run since the edit. And the failure is a session of the wrong *length*
    /// — the title and deadline are copied at press time and never re-read (P4), so a
    /// wrong snapshot cannot retime a session that is already running, and the user's
    /// remedy is `reset`. The app's own meeting starts (window strip, day list,
    /// dropdown) still re-resolve; this is the widget's path only.
    static func meetingStart(
        key: String,
        snapshot: CalendarSnapshot?,
        buffer: TimeInterval,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> (key: String, title: String, duration: TimeInterval)? {
        guard let snapshot,
              snapshot.access == .authorized,
              snapshot.isFresh(now, calendar: calendar),
              let event = snapshot.events.first(where: { $0.id == key }),
              // §4's one threshold, the same one the row's label was computed
              // against. A press that arrived after the event stopped being worth
              // timing starts nothing.
              let duration = CalendarDerivations.timeableDuration(
                  until: event.startsAt,
                  buffer: buffer,
                  now: now
              )
        else { return nil }

        return (key: event.id, title: event.title, duration: duration)
    }
}

// MARK: - Wire form

/// The action, flattened to the three scalars an App Intent parameter can carry.
///
/// In `Shared/` rather than beside the intent because it is the boundary between the
/// widget's process and the container's, and a boundary the tests cannot reach is a
/// boundary nobody checks. The intent is the only caller.
extension WidgetAction {
    /// The action without its arguments, which is all an `@Parameter` can carry.
    enum Kind: String, Sendable {
        case start, startDuration, startMeeting, pause, resume, reset, extend
    }

    var kind: Kind {
        switch self {
        case .start: .start
        case .startDuration: .startDuration
        case .startMeeting: .startMeeting
        case .pause: .pause
        case .resume: .resume
        case .reset: .reset
        case .extend: .extend
        }
    }

    /// Rebuilt from an intent's parameters. `nil` for a kind this build does not
    /// know, or for an argument that cannot be a session — a zero duration, an empty
    /// occurrence key — so a malformed request fails as "nothing happened" rather
    /// than as a session of length zero.
    init?(kind: String, duration: Double, eventKey: String) {
        switch Kind(rawValue: kind) {
        case .start: self = .start
        case .startDuration:
            guard duration > 0 else { return nil }
            self = .startDuration(duration)
        case .startMeeting:
            guard !eventKey.isEmpty else { return nil }
            self = .startMeeting(eventKey: eventKey)
        case .pause: self = .pause
        case .resume: self = .resume
        case .reset: self = .reset
        case .extend: self = .extend
        case nil: return nil
        }
    }
}
