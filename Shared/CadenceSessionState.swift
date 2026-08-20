import Foundation

/// Shared session model — the seam between the app and the widget.
///
/// The app writes the current pomodoro state via `SharedStore` and the widget
/// reads it back through the App Group container. See `SharedStore`.
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

    /// True when a phase is running and hasn't elapsed yet.
    func isActive(asOf now: Date) -> Bool {
        guard let endDate else { return false }
        return phase != .idle && endDate > now
    }

    var title: String {
        switch phase {
        case .idle: return "Cadence"
        case .focus: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    var symbol: String {
        switch phase {
        case .idle: return "timer"
        case .focus: return "brain.head.profile"
        case .shortBreak, .longBreak: return "cup.and.saucer"
        }
    }

    /// Idle placeholder used before any session exists.
    static let placeholder = CadenceSessionState()

    /// A running focus session, for widget previews/snapshots.
    static let sample = CadenceSessionState(
        phase: .focus,
        endDate: Date().addingTimeInterval(25 * 60)
    )
}
