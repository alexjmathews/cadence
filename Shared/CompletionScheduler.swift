import Foundation
import UserNotifications

/// Arms and cancels the completion alarm `CompletionAlarm` decided on (D3).
///
/// **Each writer owns its own alarm, and this is the code both of them run.** Stage 4
/// measured the constraint this shape exists for: the app and the widget extension get
/// two separate notification stores. An extension *can* schedule — it inherits the
/// containing app's authorization without prompting, `add()` succeeds, and the request
/// fires with the extension process long gone — but neither side can enumerate or
/// cancel the other's requests. `removePendingNotificationRequests` across the
/// boundary silently succeeds and changes nothing. So D3's original shape ("the app
/// schedules, intents only cancel, the app reconciles later") is not implementable in
/// either direction, and the shape that works is this one: whichever process performs
/// the transition schedules or cancels in its own store.
///
/// Which is why it lives in `Shared/` and takes its store as an argument, the way the
/// transitions take `now`. Two processes running one code path against one record
/// cannot disagree about when a session ends.
///
/// **Duplicates are handled at delivery, not here.** Press `start` on the widget and
/// then `pause` in the app and the widget's request is still armed and unreachable.
/// `CompletionAlarm.agreesWithContainer` is the answer to that — whichever process is
/// awake at fire time checks the record and suppresses a banner that disagrees with
/// it — and it is the only answer available, because the alternative is keeping two
/// stores in sync across a boundary that does not let them see each other.
///
/// An unreachable request is never at a *wrong time*: `endsAt` is stored, both processes
/// derive the trigger from it, and a fired alarm is therefore never early. It can still
/// be for the wrong *event*. `agreesWithContainer` suppresses that wherever a process is
/// awake to run it, but with the app quit there is no delegate — so start in the app,
/// quit it, pause from the widget, and at `endsAt` a stale banner announces a session
/// that is paused. Bounded to the app-quit case, and unfixable on the measured
/// constraint: an extension has no `willPresent` hook and the stores cannot see each
/// other.
struct CompletionScheduler: Sendable {

    /// The centre this scheduler talks to.
    ///
    /// It is injected because `UNUserNotificationCenter.current()` throws
    /// `bundleProxyForCurrentProcess is nil` for any process whose bundle LaunchServices
    /// does not know, which a test bundle's may or may not be. It is typed as the
    /// *protocol* rather than as the class because the class-typed version was a seam
    /// only in name: the sole value a test could inject was `nil`, so the suite could
    /// prove this file did not crash without a centre and nothing else. Three separate
    /// mutations — deleting the widget path's `reconcile`, making `.cancel` a no-op, and
    /// flipping `arming` — each survived the entire suite. Narrowed to five calls, the
    /// tests can hand it a recording double and assert what was armed and when.
    private let center: @Sendable () -> (any CompletionCentre)?

    /// Whether authorization has been asked for in this process's lifetime.
    ///
    /// D3 moves the request out of launch and into first schedule: a menu-bar app that
    /// prompts for notifications before the user has started anything is asking
    /// permission for a thing it has not yet been asked to do. `requestAuthorization`
    /// is itself idempotent — the system prompts once ever and answers from the
    /// stored grant afterwards — so this flag is a courtesy that avoids the round
    /// trip, not the mechanism that avoids a second prompt.
    private let hasRequested = Flag()

    init(center: @escaping @Sendable () -> (any CompletionCentre)? = { UNUserNotificationCenter.current() }) {
        self.center = center
    }

    /// The production scheduler. A shared instance rather than a fresh one per call so
    /// that `hasRequested` means something.
    static let shared = CompletionScheduler()

    /// Brings this process's notification store into line with what the container
    /// holds. Call it after every write, and on wake and activation.
    ///
    /// It is deliberately *not* a pair of `schedule` / `cancel` methods called from the
    /// six edges D3 names. Reconciling against the state means the same call is correct
    /// after any transition, correct when re-run against a record another process wrote,
    /// and idempotent — arming under one stable identifier replaces the pending request
    /// rather than adding a second, and cancelling nothing is free.
    /// `arming` is `false` for a caller that is merely *observing* a record another
    /// process wrote — the app on wake, on activation, or on a KVO notification. That
    /// caller still has to cancel: a widget `pause` leaves the app's alarm armed at a
    /// session that has stopped, and only the app can reach it. But it must not arm,
    /// because the process that performed the transition already armed its own, and a
    /// second one in this store is the avoidable half of D3's duplicate case — one
    /// session announcing itself twice for no reason but an activation.
    ///
    /// Arming on a write path is idempotent within a store (one stable identifier,
    /// `add()` replaces); arming on an observation path is idempotent within this
    /// store and a duplicate across the boundary. Hence the asymmetry.
    ///
    /// `now` has no default. `Shared/` owns no clock — every rule in it takes the instant
    /// as an argument so two processes reconciling one record cannot disagree about when
    /// it ends — and the one sanctioned `Date()` edge is documented on
    /// `WidgetActions.perform`. All three call sites pass `now` explicitly already.
    func reconcile(with state: SessionState, now: Date, arming: Bool = true) {
        switch CompletionAlarm.decision(for: state, now: now) {
        case .schedule(let deadline):
            guard arming else { return }
            schedule(at: deadline, state: state, now: now)
        case .disarm:
            disarm(clearingDelivered: false)
        case .retract:
            disarm(clearingDelivered: true)
        }
    }

    /// The same, read from the container. The overload exists so a caller that has just
    /// written does not have to decide which copy is authoritative — this one is (P2).
    func reconcile(with store: SharedStore, now: Date, arming: Bool = true) {
        reconcile(with: store.loadSessionState(now: now), now: now, arming: arming)
    }

    // MARK: - Arming

    private func schedule(at deadline: Date, state: SessionState, now: Date) {
        guard let center = center() else { return }

        let interval = deadline.timeIntervalSince(now)
        // `decision` already guarantees this, but a trigger built with a
        // non-positive interval traps rather than failing, and the guarantee is one
        // refactor away from someone else's function.
        guard interval > 0 else { return disarm(clearingDelivered: false) }

        let content = UNMutableNotificationContent()
        let copy = CompletionAlarm.text(for: state)
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.threadIdentifier = CompletionAlarm.threadIdentifier
        // Fires whether or not anything is awake to notice, which is D3's whole
        // premise: completion never depends on a process counting.
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: CompletionAlarm.identifier,
            content: content,
            // An interval trigger rather than a calendar one: the deadline is an
            // instant, not a wall-clock time, and a session started at 2:00 for
            // 25 minutes must still end 25 minutes later if the user changes the
            // clock or crosses a time zone in between.
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )

        // Authorization is requested here — at first schedule — rather than at launch
        // (D3). An extension inherits the app's grant and never prompts, so this is
        // effectively the app's path; the extension runs it too because the whole point
        // of the shared scheduler is that neither process has a branch the other lacks.
        let armament = Armament(center: center, request: request)
        withAuthorization(armament) { granted in
            guard granted else { return }
            armament.center.add(armament.request) { error in
                if let error {
                    NSLog("Cadence: completion alarm not scheduled — \(error.localizedDescription)")
                }
            }
        }
    }

    /// Removes this store's pending request. It cannot reach the other store's, which
    /// is the measured constraint, not an omission.
    ///
    /// `clearingDelivered` is the difference between an alarm that did its job and one
    /// that turned out to be a lie. A banner still sitting in Notification Center for a
    /// session the user has since paused or reset is the same lie as an armed alarm, and
    /// this side *can* clear its own — but a banner for a session that genuinely
    /// finished is the whole point of the feature, and clearing that one deleted the
    /// notification the user had just heard.
    private func disarm(clearingDelivered: Bool) {
        guard let center = center() else { return }
        center.removePendingNotificationRequests(withIdentifiers: [CompletionAlarm.identifier])
        if clearingDelivered {
            center.removeDeliveredNotifications(withIdentifiers: [CompletionAlarm.identifier])
        }
    }

    /// Asks once, then answers from the stored grant.
    ///
    /// `.provisional` is not used: a completion alarm the user cannot hear is not a
    /// quiet notification, it is a missing one, and D3 makes the alarm the mechanism
    /// rather than a nicety.
    private func withAuthorization(
        _ armament: Armament,
        then body: @escaping @Sendable (Bool) -> Void
    ) {
        let center = armament.center
        if hasRequested.exchangeTrue() {
            // The receiver is evaluated before the call, so these closures capture only
            // `body` — the centre itself is never carried across the boundary.
            center.currentAuthorizationStatus { status in
                body(status == .authorized || status == .provisional)
            }
            return
        }

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("Cadence: notification authorization failed — \(error.localizedDescription)")
            }
            body(granted)
        }
    }
}

// MARK: - The seam

/// The five calls `CompletionScheduler` makes on a notification centre, and nothing else.
///
/// **Why a protocol rather than the framework class.** D3 is carried out here, and a
/// concrete `UNUserNotificationCenter` is not injectable: the only value a test can
/// supply is `nil`, which proves the no-centre path does not crash and nothing about what
/// gets armed. That gap was measured — deleting `WidgetActions`' `reconcile` call,
/// no-oping `.cancel`, and flipping `arming` all left a full green suite. Narrowing the
/// dependency to what is actually used is what lets `CompletionSchedulerTests` hand it a
/// recording double, and what makes `UNUserNotificationCenter`'s conformance a near-empty
/// extension rather than a wrapper with behaviour of its own to get wrong.
///
/// Class-bound because a notification centre is a reference to one process-wide store,
/// and `Armament` has to hold that reference across an authorization callback.
protocol CompletionCentre: AnyObject {
    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)?
    )
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void
    )
    /// The authorization status alone, rather than `getNotificationSettings`.
    ///
    /// This is the one member that is not the framework's own signature, and the reason
    /// is that it would not be a seam if it were: `UNNotificationSettings` has no public
    /// initialiser, so a double could not answer a `getNotificationSettings` call at all.
    /// The scheduler reads exactly one field off it, so the protocol asks for that field.
    func currentAuthorizationStatus(_ completionHandler: @escaping @Sendable (UNAuthorizationStatus) -> Void)
}

/// The real one. Four of the five are the framework's own methods, so conforming is a
/// declaration; the fifth reads the field the scheduler wants off the settings object.
extension UNUserNotificationCenter: CompletionCentre {
    func currentAuthorizationStatus(
        _ completionHandler: @escaping @Sendable (UNAuthorizationStatus) -> Void
    ) {
        getNotificationSettings { completionHandler($0.authorizationStatus) }
    }
}

/// The centre and the request the authorization callback has to reach.
///
/// Neither a notification centre nor `UNNotificationRequest` is `Sendable`, but the
/// framework's own completion handlers are — so arming an alarm *after* an authorization
/// answer cannot be written without saying something about it. This says it in one place,
/// with the reasons: `UNUserNotificationCenter` is documented thread-safe and this is a
/// process-wide singleton either way, and `UNNotificationRequest` is immutable from the
/// moment it is constructed. The alternative — `@preconcurrency import` — would demote
/// every such error in the file to a warning, including ones that are real.
private struct Armament: @unchecked Sendable {
    let center: any CompletionCentre
    let request: UNNotificationRequest
}

/// A one-way boolean, safe to read from whichever queue a notification callback
/// arrives on. `NSLock` rather than an actor because the scheduler's callers are
/// synchronous write paths — a widget intent's `perform` and a `@MainActor`
/// controller — and neither has an `await` to spend on a flag.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    /// Sets the flag and returns what it was, so the caller can tell the first ask
    /// from every later one in a single atomic step.
    func exchangeTrue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let previous = value
        value = true
        return previous
    }
}
