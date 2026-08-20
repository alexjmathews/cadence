import Foundation

/// Shared session model — the seam between the app and the widget.
///
/// The app writes the current pomodoro state here and the widget reads it.
/// Wiring this across process boundaries needs an App Group container (which
/// requires a signing team), so for the current shell milestone the widget
/// renders `placeholder` and nothing is persisted yet. When we add the App
/// Group we'll route reads/writes through a shared `UserDefaults` suite or a
/// shared file — the model itself won't need to change.
struct CadenceSessionState: Codable, Sendable, Equatable {
    enum Phase: String, Codable, Sendable {
        case idle
        case focus
        case shortBreak
        case longBreak
    }

    var phase: Phase = .idle
    /// When the current phase ends. `nil` while idle.
    var endDate: Date? = nil

    static let placeholder = CadenceSessionState()
}
