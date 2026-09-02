import Foundation

/// The stored status of a session. Surfaces never read this directly — they read
/// `effectiveStatus(now)`, which folds in an elapsed deadline (D4).
enum SessionStatus: String, Codable, Sendable {
    case idle, running, paused, complete
}

/// The single record describing the current session. There is exactly one, and
/// there is no history: a completed session is overwritten by the next start.
///
/// Plan fields (`plannedDuration`, `title`, `linkedEventKey`) describe what the
/// session *is* and survive pause / resume / reset; run fields describe how this
/// run is going. Nothing here is a counter — a running session is a deadline, and
/// remaining time is derived (P1).
struct SessionState: Codable, Equatable, Sendable {
    var status: SessionStatus = .idle

    // Plan: survives pause / resume / reset. Replaced only by a new start.
    var plannedDuration: TimeInterval = 25 * 60
    /// `nil` means a plain duration session; the name shown is derived (P5).
    var title: String?
    /// Provenance of a meeting-linked session, not a live pointer to the event.
    var linkedEventKey: String?

    // Run.
    /// First start of this run, for the span shown in the summary.
    var startedAt: Date?
    /// Deadline. Set while running, cleared otherwise.
    var endsAt: Date?
    /// Frozen time left. Set while paused, cleared otherwise.
    var remaining: TimeInterval?
    var completedAt: Date?

    // Focus accounting: the span differs from time focused whenever a session
    // was paused, and the summary reports both.
    /// Sum of the running segments that have already finished.
    var focusedBefore: TimeInterval = 0
    /// Start of the segment currently running, if any.
    var segmentStartedAt: Date?
}
