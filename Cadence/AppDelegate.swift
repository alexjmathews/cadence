import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as a menu-bar-only accessory: no Dock icon, no window at login.
        NSApp.setActivationPolicy(.accessory)

        UNUserNotificationCenter.current().delegate = self
        NotificationManager.shared.requestAuthorization()

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

    // Handle cadence:// URLs (e.g. from Raycast via `open -g`). Runs silently in
    // the menu bar — no window is shown, and with `open -g` focus never shifts.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "cadence" {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        switch url.host {
        case "notify":
            let message = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "message" }?
                .value
            NotificationService.send(body: message ?? "This is a Cadence notification.")
        default:
            break
        }
    }

    // Show notifications even when Cadence is the foreground app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
