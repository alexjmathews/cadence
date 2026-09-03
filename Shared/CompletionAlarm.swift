import Foundation

/// What a session's stored record implies about its completion alarm (D3).
///
/// This is the *decision*, separated from the notification framework that carries it
/// out, for the reason every other rule in `Shared/` is: the app and the widget
/// extension are two writers of one record, and if they decide differently about
/// when an alarm should be armed then the four surfaces stop agreeing about when a
/// session ends. A pure function of `(SessionState, Date)` cannot diverge between
/// two processes, and a test can drive every branch of it without a container, a
/// clock, or an authorization prompt.
///
/// **It is a function of the state, not of the transition.** D3 names the edges —
/// schedule at `start` / `resume` / `extend`, cancel at `pause` / `reset` — but those
/// six edges are exactly the ones that put a record into or out of `running` with a
/// live `endsAt`, so reading the destination state covers all of them and cannot be
/// left incomplete when a seventh edge appears. It also makes the decision
/// *reconcilable*: the same function that arms an alarm at `start` can be re-run
/// against the container on wake or on activation and will arm exactly the alarm that
/// should already have been there.
enum CompletionAlarm {

    /// One stable identifier per store, which is what makes arming idempotent:
    /// `add()` under an identifier that is already pending replaces the request
    /// rather than adding a second. Two *stores* still hold one request each — that
    /// is the duplicate D3 hands to delivery, and no identifier can fix it.
    static let identifier = "cadence.completion"

    /// Groups the app's request with the extension's in Notification Center. It does
    /// not stop two banners; it stops them reading as two separate finished sessions.
    static let threadIdentifier = "cadence.session"

    enum Decision: Equatable, Sendable {
        /// Arm the alarm for this instant. Always strictly in the future.
        case schedule(at: Date)
        /// Remove any pending alarm this store holds.
        case cancel
    }

    /// The alarm the container's record implies, at `now`.
    ///
    /// Everything that is not a running session with a deadline still ahead of it
    /// cancels — `paused`, `idle`, `complete`, and the running-but-elapsed record
    /// alike. The last of those is the case worth naming: a deadline in the past
    /// cannot be scheduled (a `UNTimeIntervalNotificationTrigger` needs a positive
    /// interval) and should not be, because the session already *reads* complete on
    /// every surface (D4). An alarm for it would announce a finish the user has
    /// already been shown.
    static func decision(for state: SessionState, now: Date) -> Decision {
        guard state.status == .running,
              let endsAt = state.endsAt,
              endsAt > now
        else { return .cancel }

        return .schedule(at: endsAt)
    }

    /// The banner's copy.
    ///
    /// It names the session the way every other surface does (`displayName`, P5), so
    /// a meeting-linked session announces itself by its meeting and a plain one by
    /// its length. The fallback is computed, never stored.
    static func text(for state: SessionState) -> (title: String, body: String) {
        (title: "Session complete", body: state.displayName)
    }

    /// Whether a completion banner that is *about to be presented* still agrees with
    /// the container — the delivery-side half of D3.
    ///
    /// Two stores can hold an alarm for one session (press `start` on the widget,
    /// then `pause` in the app, and the widget's request is armed and unreachable), so
    /// a fired alarm is not evidence that the session finished. Whichever process is
    /// awake at fire time checks the record instead, and a banner that disagrees with
    /// it is suppressed.
    ///
    /// The check is `effectiveStatus`, not the stored status, for the ordinary case:
    /// with nothing awake to bank the completion the record still says `running` with
    /// an elapsed `endsAt`, and that is a session that genuinely just finished.
    ///
    /// **This is the whole mitigation, and it only covers a process that is awake.** With
    /// the app quit there is no delegate to consult, so the other store's request is
    /// presented unfiltered: start in the app, quit it, pause from the widget, and at
    /// `endsAt` a "Session complete" banner fires for a session that is paused. The
    /// *time* is never wrong — `endsAt` is stored and both processes derive the trigger
    /// from it, so an alarm is never early — but the *event* can be, and that is a stale
    /// banner for a stopped session, bounded to the app-quit case. It is not solved:
    /// Stage 4 measured that neither store can see the other's requests and an extension
    /// has no `willPresent` hook, so there is nowhere left to put the check.
    static func agreesWithContainer(_ state: SessionState, now: Date) -> Bool {
        state.effectiveStatus(now) == .complete
    }
}
