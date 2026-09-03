import Foundation

/// The word beside the numerals. Presentation only — a running session shows what
/// it *is* where the other states show where they *are*, which is why this is not
/// simply the status name.
enum StatusWord {
    static func text(for state: SessionState, at now: Date) -> String {
        switch state.effectiveStatus(now) {
        case .idle: "ready"
        case .running: state.title ?? "running"
        case .paused: "paused"
        case .complete: "complete"
        }
    }
}
