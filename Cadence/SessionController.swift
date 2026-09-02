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
    private var ticker: Timer?
    private var observers: [any NSObjectProtocol] = []
    private var suiteObserver: SuiteObserver?

    init(store: SharedStore = .shared, now: Date = Date()) {
        self.store = store
        self.now = now
        self.state = store.loadSessionState(now: now)
        self.preferences = store.loadPreferences()
        observeContainer()
        syncTicker()
    }

    // MARK: - Derived

    var status: SessionStatus { state.effectiveStatus(now) }

    /// Whether the 1 s display ticker is scheduled. Exposed for the tests that
    /// hold D1's discipline — running and nothing else.
    var isTicking: Bool { ticker != nil }

    /// The countdown as `MM:SS`, the one form all three status-item states and the
    /// dropdown numerals share.
    var clockText: String {
        let seconds = Int(state.remaining(now).rounded(.up))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
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
        let now = Date()
        self.now = now
        guard state.effectiveStatus(now) == .idle else { return }

        apply { SessionTransitions.selectDuration($0, duration: preset.duration, now: $1) }
        var next = preferences
        next.lastUsedDuration = preset.duration
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
        syncTicker()
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
        // The deadline has passed: the surfaces already read `complete` (D4), so
        // there is nothing left to redraw.
        if state.effectiveStatus(now) != .running { syncTicker() }
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
