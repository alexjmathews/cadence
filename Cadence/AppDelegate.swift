import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as a menu-bar-only accessory: no Dock icon, no window at login.
        NSApp.setActivationPolicy(.accessory)

        // Authorization is requested at first schedule, not here (D3). This is only the
        // delivery-side hook, which is where the duplicate-alarm case is handled.
        UNUserNotificationCenter.current().delegate = self

        // When the main window closes, drop back to accessory so the app keeps
        // running quietly in the menu bar without a Dock icon.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                let hasVisibleWindow = NSApp.windows.contains {
                    $0.isVisible && $0.canBecomeMain
                }
                if !hasVisibleWindow {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    // MARK: - cadence://

    /// Handles `cadence://` URLs, e.g. from Raycast via `open -g`.
    ///
    /// Nothing here activates the app: it stays an accessory, no window is shown, and
    /// with `open -g` the launch itself does not shift focus. A command from a launcher
    /// should leave the user where they were, which is the same property D2 asks of the
    /// widget's controls.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handle(url)
        }
    }

    /// The URL path and the widget's path are one path.
    ///
    /// `CadenceURL` parses to a `WidgetAction` and `WidgetActions.perform` applies it —
    /// the same function the widget's intents call, against the same container, through
    /// the same pure transitions and the same alarm scheduler. So `cadence://pause` and
    /// the widget's `Pause` cannot produce different records, and neither can drift from
    /// the dropdown's, because all three are `SessionTransitions.pause`.
    ///
    /// It writes the container rather than calling the live `SessionController`, which
    /// is not an evasion: the container is the source of truth (P2), the controller
    /// already observes it (D2), and a URL arriving while the app happens to be running
    /// therefore takes exactly the path it takes when the app has just been launched by
    /// the URL itself. One path, whichever it is.
    private func handle(_ url: URL) {
        guard let action = CadenceURL.action(for: url) else {
            NSLog("Cadence: ignoring unrecognised URL \(url.absoluteString)")
            return
        }
        // `.shared` explicitly: this process performed the transition, so this process
        // owns the alarm (D3).
        WidgetActions.perform(action, scheduler: .shared)
    }

    // MARK: - Notification delivery (D3)

    /// Presents a completion banner only if it still agrees with the container.
    ///
    /// This is the delivery-side half of D3, and it is the *only* place the duplicate
    /// case can be handled. Two notification stores can each hold an alarm for one
    /// session — press `start` on the widget and then `pause` in the app and the
    /// widget's request is armed and unreachable — so a fired alarm is not evidence that
    /// a session finished. Whichever process is awake at fire time reads the record
    /// instead, and a banner that disagrees with it is suppressed.
    ///
    /// **What this does not cover, stated plainly.** A notification delivered while the
    /// app is quit has no delegate to consult, so a stale alarm from the other store
    /// surfaces unfiltered — and that is not merely a duplicate. Start a session in the
    /// app, quit the app, then pause from the widget: the widget cancels only its own
    /// store, nothing is running to consult this delegate, and at `endsAt` a "Session
    /// complete" banner announces a session that is paused. The *time* is never wrong —
    /// `endsAt` is stored and both processes derive the trigger from it, so an alarm is
    /// never early — but the event can be, so what is bounded is a **stale banner for a
    /// stopped session, bounded to the app-quit case**. `threadIdentifier` groups the
    /// pair in Notification Center so two banners read as one session rather than two.
    /// Neither this nor keeping the stores in sync is available as a fix: Stage 4
    /// measured that neither store can see the other's requests, and an extension has no
    /// `willPresent` hook to run this check in.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.identifier == CompletionAlarm.identifier else {
            // Not ours. Present it rather than swallowing it — this delegate is the
            // process's, not this feature's.
            return Self.present
        }

        let now = Date()
        guard CompletionAlarm.agreesWithContainer(
            SharedStore.shared.loadSessionState(now: now),
            now: now
        ) else { return [] }

        return Self.present
    }

    /// **`.list` is not optional here.** `.banner` alone shows the transient banner and
    /// plays the sound, then lets the notification evaporate: it is `.list` that files it
    /// in Notification Center. Omitting it produced a completion the user could hear and
    /// never find afterwards — and because `willPresent` is consulted only while the app
    /// is running, which for a menu-bar app is always, that was every completion.
    ///
    /// A finished session is a thing to acknowledge, not to let evaporate (data model
    /// §5), and that has to hold for the notification as much as for the `complete`
    /// state itself — the alarm is what tells a user who was away from the screen.
    private static let present: UNNotificationPresentationOptions = [.banner, .list, .sound]
}
