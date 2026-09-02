import Foundation
import XCTest
@testable import Cadence

/// A fixed afternoon to write transitions against, so every assertion reads as a
/// wall-clock time rather than an offset.
enum Clock {
    static let timeZone = TimeZone(identifier: "America/New_York")!
    static let locale = Locale(identifier: "en_US_POSIX")

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }

    /// A time on 4 March 2026, in `timeZone`.
    static func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        on(day: 4, hour, minute, second)
    }

    static func on(day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        let components = DateComponents(
            timeZone: timeZone,
            year: 2026, month: 3, day: day,
            hour: hour, minute: minute, second: second
        )
        return calendar.date(from: components)!
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}

let minute: TimeInterval = 60

/// macOS separates the day period with a narrow no-break space; assertions read
/// better against an ordinary one.
func normalizingSpaces(_ string: String?) -> String? {
    string?
        .replacingOccurrences(of: "\u{202F}", with: " ")
        .replacingOccurrences(of: "\u{00A0}", with: " ")
}

extension SessionState {
    /// An idle session with a plan and a surviving title, as reset leaves things.
    static func idle(
        plannedDuration: TimeInterval = 25 * minute,
        title: String? = nil,
        linkedEventKey: String? = nil
    ) -> SessionState {
        SessionState(
            plannedDuration: plannedDuration,
            title: title,
            linkedEventKey: linkedEventKey
        )
    }

    static func running(
        plannedDuration: TimeInterval = 25 * minute,
        title: String? = nil,
        linkedEventKey: String? = nil,
        startedAt: Date,
        endsAt: Date,
        focusedBefore: TimeInterval = 0,
        segmentStartedAt: Date
    ) -> SessionState {
        SessionState(
            status: .running,
            plannedDuration: plannedDuration,
            title: title,
            linkedEventKey: linkedEventKey,
            startedAt: startedAt,
            endsAt: endsAt,
            focusedBefore: focusedBefore,
            segmentStartedAt: segmentStartedAt
        )
    }

    static func paused(
        plannedDuration: TimeInterval = 25 * minute,
        title: String? = nil,
        startedAt: Date,
        remaining: TimeInterval,
        focusedBefore: TimeInterval
    ) -> SessionState {
        SessionState(
            status: .paused,
            plannedDuration: plannedDuration,
            title: title,
            startedAt: startedAt,
            remaining: remaining,
            focusedBefore: focusedBefore
        )
    }

    static func complete(
        plannedDuration: TimeInterval = 25 * minute,
        title: String? = nil,
        startedAt: Date,
        completedAt: Date,
        focusedBefore: TimeInterval
    ) -> SessionState {
        SessionState(
            status: .complete,
            plannedDuration: plannedDuration,
            title: title,
            startedAt: startedAt,
            completedAt: completedAt,
            focusedBefore: focusedBefore
        )
    }
}

/// Asserts the §2.1 invariants: anything not listed for a status is nil or zero.
func assertInvariants(
    _ state: SessionState,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch state.status {
    case .idle:
        XCTAssertNil(state.startedAt, "idle keeps no startedAt", file: file, line: line)
        XCTAssertNil(state.endsAt, "idle keeps no endsAt", file: file, line: line)
        XCTAssertNil(state.remaining, "idle keeps no remaining", file: file, line: line)
        XCTAssertNil(state.completedAt, "idle keeps no completedAt", file: file, line: line)
        XCTAssertNil(state.segmentStartedAt, "idle keeps no segment", file: file, line: line)
        XCTAssertEqual(state.focusedBefore, 0, "idle banks no focus", file: file, line: line)
    case .running:
        XCTAssertNotNil(state.startedAt, "running has a start", file: file, line: line)
        XCTAssertNotNil(state.endsAt, "running has a deadline", file: file, line: line)
        XCTAssertNotNil(state.segmentStartedAt, "running has a segment", file: file, line: line)
        XCTAssertNil(state.remaining, "running freezes nothing", file: file, line: line)
        XCTAssertNil(state.completedAt, "running is not complete", file: file, line: line)
    case .paused:
        XCTAssertNotNil(state.startedAt, "paused has a start", file: file, line: line)
        XCTAssertNotNil(state.remaining, "paused freezes remaining", file: file, line: line)
        XCTAssertNil(state.endsAt, "paused has no deadline", file: file, line: line)
        XCTAssertNil(state.segmentStartedAt, "paused runs no segment", file: file, line: line)
        XCTAssertNil(state.completedAt, "paused is not complete", file: file, line: line)
    case .complete:
        XCTAssertNotNil(state.startedAt, "complete has a start", file: file, line: line)
        XCTAssertNotNil(state.completedAt, "complete has a completion", file: file, line: line)
        XCTAssertNil(state.endsAt, "complete has no deadline", file: file, line: line)
        XCTAssertNil(state.remaining, "complete freezes nothing", file: file, line: line)
        XCTAssertNil(state.segmentStartedAt, "complete runs no segment", file: file, line: line)
    }
    XCTAssertGreaterThan(state.plannedDuration, 0, "every status keeps a plan", file: file, line: line)
}
