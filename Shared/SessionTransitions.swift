import Foundation

/// The state machine. Every transition is a pure function of the current state,
/// the preferences, and an injected `now`, so the app and the widget extension —
/// two independent writers of the same record — compute identical results (D2).
/// Nothing here reads the clock; nothing here has side effects.
///
/// Guard violations return the input state unchanged. A widget rendered from a
/// stale timeline can legitimately ask for an illegal transition, and that must
/// cost nothing.
enum SessionTransitions {
    static let extensionStep: TimeInterval = 5 * 60

    // MARK: - Reconciliation

    /// Folds an elapsed deadline into the stored record.
    ///
    /// Nothing has to be awake for a session to finish (D3/D4): the deadline may
    /// have passed while the app was quit or the machine asleep. Every transition
    /// reconciles first, so a request arriving after the deadline is judged
    /// against the state the user actually sees.
    static func reconciled(_ state: SessionState, now: Date) -> SessionState {
        state.effectiveStatus(now) == .complete && state.status == .running
            ? complete(state, now: now)
            : state
    }

    // MARK: - Transitions

    /// Replaces the plan and begins a run. Legal from `idle` and from `complete`
    /// (where it is the "Start another" edge); never from `running` or `paused`,
    /// which is what makes a second timer unstartable.
    static func start(
        _ state: SessionState,
        duration: TimeInterval,
        title: String? = nil,
        linkedEventKey: String? = nil,
        now: Date
    ) -> SessionState {
        let state = reconciled(state, now: now)
        guard state.status == .idle || state.status == .complete else { return state }
        guard duration > 0 else { return state }

        var next = state
        next.status = .running
        next.plannedDuration = duration
        next.title = title
        next.linkedEventKey = linkedEventKey
        next.startedAt = now
        next.endsAt = now.addingTimeInterval(duration)
        next.remaining = nil
        next.completedAt = nil
        next.focusedBefore = 0
        next.segmentStartedAt = now
        return next
    }

    /// The `complete → running` edge. A full plan replacement, identical to
    /// `start`; named separately because the surfaces label it differently.
    static func startAnother(
        _ state: SessionState,
        duration: TimeInterval,
        title: String? = nil,
        linkedEventKey: String? = nil,
        now: Date
    ) -> SessionState {
        start(state, duration: duration, title: title, linkedEventKey: linkedEventKey, now: now)
    }

    /// Freezes the remaining time and banks the segment just finished.
    static func pause(_ state: SessionState, now: Date) -> SessionState {
        let state = reconciled(state, now: now)
        guard state.status == .running, let endsAt = state.endsAt else { return state }

        var next = state
        next.status = .paused
        next.remaining = max(0, endsAt.timeIntervalSince(now))
        next.focusedBefore += bankedFocus(from: state.segmentStartedAt, to: now)
        next.endsAt = nil
        next.segmentStartedAt = nil
        return next
    }

    /// Materialises a fresh deadline from the frozen remainder, so time spent
    /// paused never counts against the session.
    static func resume(_ state: SessionState, now: Date) -> SessionState {
        let state = reconciled(state, now: now)
        guard state.status == .paused, let remaining = state.remaining else { return state }

        var next = state
        next.status = .running
        next.endsAt = now.addingTimeInterval(remaining)
        next.remaining = nil
        next.segmentStartedAt = now
        return next
    }

    /// Clears the run and the focus accounting, keeping the plan — the clock goes
    /// back to its full duration and the title survives (P3).
    static func reset(_ state: SessionState, now: Date) -> SessionState {
        let state = reconciled(state, now: now)
        guard state.status != .idle else { return state }

        var next = state
        next.status = .idle
        next.startedAt = nil
        next.endsAt = nil
        next.remaining = nil
        next.completedAt = nil
        next.focusedBefore = 0
        next.segmentStartedAt = nil
        return next
    }

    /// The deadline being reached. Legal only once `endsAt` is in the past, and
    /// `completedAt` is the deadline rather than `now`: the session finished when
    /// it said it would, however late anything noticed.
    static func complete(_ state: SessionState, now: Date) -> SessionState {
        guard state.status == .running, let endsAt = state.endsAt, endsAt <= now else {
            return state
        }

        var next = state
        next.status = .complete
        next.completedAt = endsAt
        next.focusedBefore += bankedFocus(from: state.segmentStartedAt, to: endsAt)
        next.endsAt = nil
        next.remaining = nil
        next.segmentStartedAt = nil
        return next
    }

    /// Adds time to a finished session, growing the plan with it so progress and
    /// focus stay meaningful. Legal only from `complete`.
    ///
    /// The new deadline runs from `max(now, completedAt)`: returning to a session
    /// that finished ten minutes ago should buy five more minutes from now, not a
    /// deadline already in the past.
    static func extend(
        _ state: SessionState,
        by step: TimeInterval = extensionStep,
        now: Date
    ) -> SessionState {
        let state = reconciled(state, now: now)
        guard state.status == .complete, let completedAt = state.completedAt else { return state }
        guard step > 0 else { return state }

        var next = state
        next.status = .running
        next.endsAt = max(now, completedAt).addingTimeInterval(step)
        next.plannedDuration += step
        next.segmentStartedAt = now
        next.completedAt = nil
        next.remaining = nil
        return next
    }

    /// Re-scopes the plan. Legal only in `idle`: changing the duration under a
    /// frozen `remaining` would leave progress and the resume deadline ambiguous,
    /// so a paused session is re-scoped by resetting first.
    static func selectDuration(_ state: SessionState, duration: TimeInterval, now: Date) -> SessionState {
        let state = reconciled(state, now: now)
        guard state.status == .idle, duration > 0 else { return state }

        var next = state
        next.plannedDuration = duration
        return next
    }

    // MARK: - Helpers

    /// Time earned by a running segment. Clamped at zero so a wall clock that
    /// moved backwards cannot subtract focus that was already banked.
    private static func bankedFocus(from segmentStartedAt: Date?, to end: Date) -> TimeInterval {
        guard let segmentStartedAt else { return 0 }
        return max(0, end.timeIntervalSince(segmentStartedAt))
    }
}
