import AppIntents

/// Sends a Cadence notification. Because it lives in `Shared/`, both the app and
/// the widget extension compile it: the widget uses it via `Button(intent:)`, and
/// the app exposes it to Shortcuts/Siri/Spotlight through `CadenceShortcuts`.
struct SendNotificationIntent: AppIntent {
    static var title: LocalizedStringResource { "Send Cadence Notification" }
    static var description: IntentDescription { IntentDescription("Sends a local notification from Cadence.") }

    // Keep it silent — never foreground the app when the intent runs.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Message", default: "This is a Cadence notification.")
    var message: String

    init() {}

    init(message: String) {
        self.message = message
    }

    func perform() async throws -> some IntentResult {
        NotificationService.send(body: message)
        return .result()
    }
}
