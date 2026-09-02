import Foundation

/// User settings that outlive any one session.
///
/// The end-early buffer is a preference rather than a session field: it is
/// materialised into `endsAt` at the moment a meeting timer starts (P4), so every
/// surface computes the same deadline and changing it mid-session retimes nothing.
struct Preferences: Codable, Equatable, Sendable {
    /// Seconds to finish before a meeting begins. 0 is off.
    var endEarlyBuffer: TimeInterval = 120
    /// Last duration the user chose, so idle shows something sensible.
    var lastUsedDuration: TimeInterval = 25 * 60
}
