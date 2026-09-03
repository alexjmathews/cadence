import Foundation

/// `DateFormatter`s kept alive across renders, one per locale and time zone. Shared
/// by every surface that prints a time — the status line, the calendar strip, and the
/// day list — because building one per second to print times that change once a
/// minute is worth not doing. In `Shared/` because the widget extension prints the
/// same times from its own process.
///
/// `@unchecked Sendable` is earned by the lock: every access to the dictionary is
/// inside it, and a `DateFormatter` handed out is only ever read.
final class FormatterCache: @unchecked Sendable {
    private let template: String
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    init(template: String) {
        self.template = template
    }

    func formatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let key = "\(locale.identifier)|\(timeZone.identifier)"

        lock.lock()
        defer { lock.unlock() }
        if let cached = formatters[key] { return cached }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter
    }
}
