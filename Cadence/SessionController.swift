import AppKit
import Foundation

/// The app's live view of the session. Owns the in-memory copy, writes through to
/// the App Group on every mutation, re-reads when another process writes, and owns
/// the display ticker.
///
/// It is a cache, never the truth (P2). Every mutation goes through a
/// `SessionTransitions` function with `Date()` captured here — the clock belongs to
/// the app layer, so `Shared/` stays pure and testable.
@MainActor
@Observable
final class SessionController {

    /// The stored record, already reconciled against the clock it was read with.
    private(set) var state: SessionState
    private(set) var preferences: Preferences

    /// The clock the surfaces render against. Advanced by the ticker (D1) and by
    /// every mutation, so reading it in a view body is what subscribes that body
    /// to the countdown.
    private(set) var now: Date

    private let store: SharedStore
    private let scheduler: CompletionScheduler?
    private var ticker: Timer?
    private var observers: [any NSObjectProtocol] = []
    private var suiteObserver: SuiteObserver?

    /// `scheduler` defaults to `nil`, and `CadenceApp` passes `.shared`. A test that
    /// forgot the argument would otherwise arm real alarms and raise a real
    /// authorization prompt on the machine running the suite;
    /// `UNUserNotificationCenter.current()` additionally throws
    /// `bundleProxyForCurrentProcess is nil` for a process whose bundle LaunchServices
    /// does not know. Neither is a side effect a unit test should acquire by omission.
    init(
        store: SharedStore = .shared,
        scheduler: CompletionScheduler? = nil,
        now: Date = Date()
    ) {
        self.store = store
        self.scheduler = scheduler
        self.now = now
        self.state = store.loadSessionState(now: now)
        self.preferences = store.loadPreferences()
        observeContainer()
        syncTicker()
        // A relaunch with a session already running is a *first schedule*, not launch
        // work: this process's notification store is empty (the store belongs to the
        // process, and Stage 4 measured that it does not survive it), so the alarm the
        // record implies has to be armed here or it does not exist. Which is also why
        // this is where D3's authorization request can first surface — it is a
        // schedule, and D3 asks only that it not be launch boilerplate.
        //
        // A session whose deadline passed while the app was quit is banked first, so
        // the alarm reconciles against a record that agrees with what the surfaces
        // are about to draw.
        bankCompletion(now: now)
        reconcileAlarm()
    }

    // MARK: - Derived

    var status: SessionStatus { state.effectiveStatus(now) }

    /// Whether the 1 s display ticker is scheduled. Exposed for the tests that
    /// hold D1's discipline — running and nothing else.
    var isTicking: Bool { ticker != nil }

    /// The countdown, in the one form every surface shares — window numerals,
    /// dropdown numerals, and the status-item pill (`ClockFormatter`).
    var clockText: String {
        ClockFormatter.text(state.remaining(now))
    }

    /// `45 minutes` plus the two half-hour targets, rebuilt against the current
    /// tick so the clock rows stay honest while the dropdown is open.
    var presets: [DurationPreset] { DurationPreset.all(at: now) }

    // MARK: - Actions

    func start() {
        apply { SessionTransitions.start($0, duration: $0.plannedDuration, now: $1) }
    }

    func startAnother() {
        apply { SessionTransitions.startAnother($0, duration: $0.plannedDuration, now: $1) }
    }

    /// A meeting-linked start, from the window strip, the day list, or the dropdown's
    /// `To <event>` row — all three call this, which is what makes them produce
    /// identical state.
    ///
    /// The deadline arrives already materialised (P4): `CalendarController` re-resolved
    /// the occurrence key against the live event store and subtracted the saved buffer
    /// before this was called, so the session copies a title and a duration and keeps
    /// no pointer to the event. `linkedEventKey` is provenance only — nothing reads it
    /// back to retime anything.
    ///
    /// The duration is computed against the transition's own `now` rather than passed
    /// in, so the session ends at the buffered instant regardless of how long the press
    /// took to reach the container.
    func startMeeting(_ meeting: MeetingStart) {
        apply { state, now in
            let duration = meeting.endsAt.timeIntervalSince(now)
            guard duration > 0 else { return state }
            return SessionTransitions.start(
                state,
                duration: duration,
                title: meeting.title,
                linkedEventKey: meeting.key,
                now: now
            )
        }
    }

    func pause() {
        apply(SessionTransitions.pause)
    }

    func resume() {
        apply(SessionTransitions.resume)
    }

    func reset() {
        apply(SessionTransitions.reset)
    }

    func extend() {
        apply { SessionTransitions.extend($0, now: $1) }
    }

    /// Re-scopes the plan from a preset row, remembering the choice — the only
    /// writer of `lastUsedDuration`.
    ///
    /// The guard is the precondition itself, not a post-hoc comparison of the
    /// resulting plan. `selectDuration` is legal only in `idle` (§5) and rejects
    /// illegally by returning its input, which is indistinguishable from a
    /// duration that was already selected; reading the status directly is what
    /// keeps a running session from rewriting the preference underneath itself.
    func select(_ preset: DurationPreset) {
        selectDuration(preset.duration)
    }

    /// The editable numerals' commit path, and the one `select(_:)` funnels
    /// through. Same guard, same preference write: a typed duration and a preset
    /// row are the same act (§5's third guard covers "presets and the editable
    /// numerals alike").
    ///
    /// The preference follows the *plan*, not the press. `SessionTransitions.
    /// selectDuration` guards `duration > 0` as well as the status and rejects by
    /// returning its input, so a press the transition refused must not leave
    /// `lastUsedDuration: 0` behind it — §2.2 says that field exists so idle shows
    /// something sensible, and zero is not.
    func selectDuration(_ duration: TimeInterval) {
        let now = Date()
        self.now = now
        guard state.effectiveStatus(now) == .idle else { return }

        apply { SessionTransitions.selectDuration($0, duration: duration, now: $1) }

        // `apply` transitions from the container, which may hold a newer record than
        // the status checked above, and a dropped write leaves the plan alone. Both
        // read the same way here: the plan did not move, so neither does the
        // preference.
        guard status == .idle, state.plannedDuration == duration else { return }
        guard preferences.lastUsedDuration != duration else { return }

        var next = preferences
        next.lastUsedDuration = duration
        save(next)
    }

    /// Writes the end-early buffer (§2.2). Legal in every state: the buffer is
    /// materialised into a deadline at start time (P4), so changing it never
    /// retimes the session that is already running.
    func setBuffer(_ seconds: TimeInterval) {
        guard seconds != preferences.endEarlyBuffer else { return }
        var next = preferences
        next.endEarlyBuffer = seconds
        save(next)
    }

    // MARK: - Mutation

    /// Transitions from what the container holds, not from the cached copy.
    ///
    /// KVO delivers another process's write asynchronously, so a press landing
    /// inside that latency window would otherwise be computed against a stale base
    /// and write it straight back over the newer record. Re-reading costs one
    /// decode per deliberate user action and removes the race entirely (D2).
    private func apply(_ transition: (SessionState, Date) -> SessionState) {
        let now = Date()
        self.now = now

        let base = store.loadSessionState(now: now)
        let next = transition(base, now)

        // Adopt the container's version first, whatever the transition decided:
        // the cache may have been trailing another writer, and a rejected
        // transition still returns the reconciled base.
        if base != state {
            state = base
            syncTicker()
        }
        guard next != base else { return }

        // A dropped write must not leave a live state disagreeing with disk: the
        // container is canonical, so an unwritten transition simply did not happen.
        guard store.save(next) else {
            NSLog("Cadence: transition dropped — the container refused the write")
            return
        }
        state = next
        syncTicker()
        reconcileAlarm()
    }

    // MARK: - Completion alarm (D3)

    /// Brings this process's notification store into line with the record just
    /// written. Every write path funnels through `apply`, so this one call covers all
    /// six edges D3 names — `start` / `resume` / `extend` arm, `pause` / `reset` and a
    /// banked completion cancel — because `CompletionAlarm` decides from the
    /// destination *state* rather than from which transition produced it.
    ///
    /// It runs on the app's own store only. A widget intent arms its own, in its own
    /// store, through the same `Shared/` scheduler; neither can see the other's, which
    /// is the measured constraint D3 was amended for.
    private func reconcileAlarm(arming: Bool = true) {
        scheduler?.reconcile(with: state, now: now, arming: arming)
    }

    private func save(_ preferences: Preferences) {
        guard store.save(preferences) else { return }
        self.preferences = preferences
    }

    // MARK: - Container observation

    /// Widget intents and `cadence://` callers write the container directly (D2),
    /// so the app watches it rather than trusting what it last wrote.
    ///
    /// KVO on the suite is the signal that actually carries another process's
    /// write; `UserDefaults.didChangeNotification` was measured firing zero times
    /// for one, so it is kept for D2's own-process case and scoped to this suite —
    /// unscoped it fires for every `UserDefaults.standard` write anywhere in the
    /// process, each one paying for a re-read and a redraw. Activation and wake are
    /// the belt-and-braces re-reads.
    private func observeContainer() {
        let center = NotificationCenter.default
        let suite = UserDefaults(suiteName: store.suiteName)

        suiteObserver = SuiteObserver(
            suite: suite,
            keys: [SharedStore.Key.sessionState, SharedStore.Key.preferences]
        ) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }

        observers = [
            center.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: suite,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
        ]
    }

    /// Re-reads both records. `loadSessionState` reconciles, so a deadline that
    /// elapsed while the machine slept is folded in on the way back.
    func refresh() {
        let now = Date()
        self.now = now
        let stored = store.loadSessionState(now: now)
        if stored != state { state = stored }
        let storedPreferences = store.loadPreferences()
        if storedPreferences != preferences { preferences = storedPreferences }
        // Wake is the case the ticker cannot cover: `syncTicker` below would invalidate
        // it for a session that completed while the machine slept, so the tick that
        // would have banked the completion never arrives. Banking here is what makes
        // "the deadline elapsed while asleep" persist rather than merely render.
        bankCompletion(now: now)
        syncTicker()
        // Observation, not a write: cancel an alarm the record no longer justifies —
        // a widget `pause` can only be reached from this side — but do not arm one the
        // writer already armed in its own store.
        reconcileAlarm(arming: false)
    }

    // MARK: - Ticker (D1)

    /// One second, and only while running. The ticker exists to redraw: it never
    /// decrements stored state and never fires `complete`, which is derived from
    /// the deadline instead (D4). A throttled or sleeping ticker can cost a frame,
    /// never a minute.
    private func syncTicker() {
        // `now` is refreshed by every caller immediately before this runs, so the
        // ticker's fate is judged against the same instant as the render it drives.
        guard state.effectiveStatus(now) == .running else {
            ticker?.invalidate()
            ticker = nil
            return
        }
        guard ticker == nil else { return }

        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            // The run loop owns the timer, so an outlived controller has to say so.
            guard let self else { return timer.invalidate() }
            MainActor.assumeIsolated { self.tick() }
        }
        ticker.tolerance = 0.1
        // Common modes keep the countdown moving while a menu or a drag has the
        // run loop in a tracking mode.
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func tick() {
        now = Date()
        guard state.effectiveStatus(now) != .running else { return }

        // The deadline has passed, so bank it.
        bankCompletion(now: now)
        // `bankCompletion` re-syncs only when the record moved, and the ticker has to
        // stop either way.
        syncTicker()
    }

    /// Persists a completion the deadline already decided.
    ///
    /// Every surface already *reads* complete (D4), but the stored record still says
    /// `running` with an elapsed `endsAt` — so `completedAt` is nil, the window's
    /// summary line has nothing to print, and, now that D3 gives each writer an alarm
    /// to cancel, the container claims a session is running that this process is about
    /// to cancel the alarm for.
    ///
    /// This cannot go through `apply`, and the reason is the whole of the defect it
    /// fixes. `apply` bases its transition on `loadSessionState`, which reconciles on
    /// read; reconciling *that* returns it unchanged, so `next != base` was always
    /// false and the write never happened. The comparison has to be against the record
    /// as **stored**, which is what `loadStoredSessionState` is for.
    ///
    /// It is not the ticker deciding completion (D1): the deadline decided, and this
    /// merely persists the derived result, on the same terms every other entry point
    /// (load, refresh, any transition) already reconciles. And it is idempotent — an
    /// already-banked completion reconciles to itself, so the guard holds and nothing
    /// is written or reloaded.
    ///
    /// `now` is a parameter rather than a fresh `Date()` because this runs from `init`,
    /// *after* the injected clock has been stored: capturing wall-clock here would
    /// overwrite the value `SessionController(store:scheduler:now:)` was handed before
    /// the initialiser had returned, so a test injecting a fixed clock would silently get
    /// the real one. The callers that do own a fresh instant pass it.
    private func bankCompletion(now: Date) {
        self.now = now

        let stored = store.loadStoredSessionState()
        let banked = SessionTransitions.reconciled(stored, now: now)
        guard banked != stored else { return }

        guard store.save(banked) else {
            NSLog("Cadence: completion not banked — the container refused the write")
            return
        }
        state = banked
        // The banked record is `complete`, so this cancels — the honest end of the
        // alarm's life, rather than leaving a request armed for a deadline that has
        // already been announced.
        reconcileAlarm()
    }
}

/// Key-value observation over the App Group suite, which is the signal a write
/// from another process actually raises. `UserDefaults` has no typed observation
/// for dynamic keys, so this is the untyped path with the `NSObject` it requires
/// kept out of the controller.
private final class SuiteObserver: NSObject {
    private let suite: UserDefaults?
    private let keys: [String]
    private let onChange: @Sendable () -> Void

    init(suite: UserDefaults?, keys: [String], onChange: @escaping @Sendable () -> Void) {
        self.suite = suite
        self.keys = keys
        self.onChange = onChange
        super.init()
        for key in keys {
            suite?.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
    }

    deinit {
        for key in keys {
            suite?.removeObserver(self, forKeyPath: key)
        }
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        DispatchQueue.main.async { [onChange] in onChange() }
    }
}
