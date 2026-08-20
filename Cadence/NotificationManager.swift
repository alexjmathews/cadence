import Foundation
import UserNotifications

final class NotificationManager: Sendable {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, error in
            if let error {
                NSLog("Cadence: notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    /// Fires an immediate local notification to prove the pipeline works.
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Cadence"
        content.body = "Test notification — the pipeline works."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Cadence: failed to send notification: \(error.localizedDescription)")
            }
        }
    }
}
