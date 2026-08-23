import Foundation
import UserNotifications

/// Posts a local notification. Lives in `Shared/` so every entry point — the
/// app's menu, the `cadence://notify` URL handler, and the `SendNotificationIntent`
/// used by the widget — funnels through the same code.
enum NotificationService {
    static func send(
        title: String = "Cadence",
        body: String = "This is a Cadence notification."
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Cadence: failed to send notification: \(error.localizedDescription)")
            }
        }
    }
}
