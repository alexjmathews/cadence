import AppIntents

/// Surfaces Cadence's intents to Spotlight and Siri with spoken phrases, with no
/// setup required from the user. This also makes the action discoverable as an
/// Apple Shortcut, which is how Raycast (and the Action button) can run it.
struct CadenceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendNotificationIntent(),
            phrases: [
                "Send a \(.applicationName) notification",
                "Notify me with \(.applicationName)"
            ],
            shortTitle: "Send Notification",
            systemImageName: "bell.badge"
        )
    }
}
