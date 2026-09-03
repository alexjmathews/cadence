import Foundation

/// The `cadence://` command surface, parsed.
///
/// It is a pure function from a `URL` to a `WidgetAction` — the *same* vocabulary the
/// widget's controls speak — so a Raycast command and a widget button are two spellings
/// of one transition rather than two implementations of one. That is what makes "the
/// same action from every surface produces the same record" a property of the code
/// instead of a thing to test four times.
///
/// In `Shared/` because parsing is the whole of the risk here: a URL arrives from
/// outside the app, and a grammar that lives in an `AppDelegate` method is a grammar no
/// test can reach.
enum CadenceURL {
    static let scheme = "cadence"

    /// The commands, as the host component spells them. `startAnother` is not among
    /// them: it is `start` from the complete state, and the transition's own guard is
    /// what makes the two one action (§5).
    enum Command: String {
        case start, pause, resume, reset, extend
    }

    /// Query keys `start` accepts. Both are integers; `minutes` wins when both appear,
    /// because a caller that sent both meant the coarser one it typed.
    enum Key {
        static let minutes = "minutes"
        static let seconds = "seconds"
    }

    /// The action a URL asks for, or `nil` for anything this build does not recognise.
    ///
    /// **Everything unrecognised is `nil`, and `nil` does nothing.** A URL is the one
    /// input that arrives from outside the app — from a Raycast command, a Shortcut, a
    /// terminal, or a typo — and guessing a transition from a malformed request is how
    /// an app comes to start a session nobody asked for. So: a wrong scheme, an unknown
    /// host, a non-numeric duration, a duration of zero, and a duration past what
    /// `ClockFormatter` can print are all the same answer.
    ///
    /// The upper bound is `ClockFormatter.maximumDuration`, not an arbitrary sanity
    /// limit. The window's numerals are two fields of three and two digits (D9) and the
    /// countdown never rolls over into hours, so a session longer than `999:59` is one
    /// the surfaces cannot draw and the numerals cannot express — which makes it a
    /// malformed request, not a long one.
    static func action(for url: URL) -> WidgetAction? {
        guard url.scheme?.lowercased() == scheme,
              let host = url.host()?.lowercased(),
              let command = Command(rawValue: host),
              // The command is the *host*, and a URL carrying a path as well is not one
              // of these commands with something extra on it — it is a URL this build
              // does not understand. `cadence://start/extra` reads like it means
              // something, and refusing it is how it stays meaning nothing.
              url.path().isEmpty || url.path() == "/"
        else { return nil }

        switch command {
        case .pause: return .pause
        case .resume: return .resume
        case .reset: return .reset
        case .extend: return .extend

        case .start:
            let query = queryItems(of: url)
            // No duration at all is the documented plain `cadence://start`: run the
            // stored plan, which is what the dropdown's own `Start` does.
            guard let duration = duration(in: query) else {
                return query[Key.minutes] == nil && query[Key.seconds] == nil
                    ? .start
                    // A duration *was* asked for and could not be honoured. Falling
                    // back to the stored plan here would silently start a session of a
                    // length the caller did not ask for, which is worse than nothing
                    // happening.
                    : nil
            }
            return .startDuration(duration)
        }
    }

    /// The requested duration in seconds, or `nil` when none was asked for or the one
    /// asked for is not expressible.
    private static func duration(in query: [String: String]) -> TimeInterval? {
        let seconds: Int
        if let minutes = query[Key.minutes] {
            guard let value = wholeNumber(minutes) else { return nil }
            seconds = value * 60
        } else if let raw = query[Key.seconds] {
            guard let value = wholeNumber(raw) else { return nil }
            seconds = value
        } else {
            return nil
        }

        guard seconds > 0, TimeInterval(seconds) <= ClockFormatter.maximumDuration else {
            return nil
        }
        return TimeInterval(seconds)
    }

    /// A whole number and nothing else.
    ///
    /// ASCII digits and nothing else, which is stricter than `Int(_:)` and deliberately
    /// so. `Int("+5")` is 5 and `Int("٥")` is 5, and a URL is the one input that arrives
    /// from outside the app — the same argument D9 makes for refusing non-digits at the
    /// numeral field rather than validating afterwards. `12.5`, `1e3`, an empty string
    /// and a signed value are all simply not durations this grammar has.
    private static func wholeNumber(_ text: String) -> Int? {
        guard !text.isEmpty,
              text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(text),
              value > 0
        else { return nil }
        return value
    }

    /// The last value for each key, lowercased.
    ///
    /// Last-wins rather than first-wins is arbitrary but has to be decided; what
    /// matters is that a repeated key cannot make the parse depend on the order the
    /// components happened to be enumerated in.
    private static func queryItems(of url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else { return [:] }

        var query: [String: String] = [:]
        for item in items {
            guard let value = item.value else { continue }
            query[item.name.lowercased()] = value.trimmingCharacters(in: .whitespaces)
        }
        return query
    }
}
