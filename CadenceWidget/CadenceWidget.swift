import SwiftUI
import WidgetKit

/// One entry: everything the two families draw, already decided. The provider does
/// the reading and `WidgetPresentation` does the deciding, so the views take values
/// rather than a store.
struct CadenceEntry: TimelineEntry {
    let date: Date
    let tile: WidgetTile
    let pane: WidgetPane
}

/// The widget's read side: a pure reader over the App Group.
///
/// **The countdown and the progress rule need different things.** The running clock is
/// a `Text(timerInterval:)`, which SwiftUI advances itself from a single entry — no
/// reload, nothing awake. The rule has no such affordance: it is drawn from
/// `tile.progress`, a number computed when the entry was made, so one entry per session
/// draws it once at the fraction it held then and leaves it there. That is exactly what
/// shipped — a widget whose digits counted down past a rule that never moved.
///
/// So a running session gets a *series* of entries at fixed instants, and the system
/// swaps views at those dates without waking the extension. The series is one read of
/// the container replayed at each date, not a read per entry, and it is bounded (see
/// `progressDates`) so a nine-hour meeting timer costs the same as a five-minute one.
///
/// Every other state is a still that only a write can change, and a write reloads every
/// timeline through `SharedStore` on its way past. There is still no ticker here; D1 is
/// the menu bar's problem.
struct CadenceProvider: TimelineProvider {
    /// The rule advances in at most this many steps. Sixty puts a 25-minute session on a
    /// 25-second cadence, which moves a 151 pt rule about 2.5 pt at a time — visible
    /// motion without a timeline the system has to hold a thousand entries for.
    private static let maximumProgressEntries = 60
    /// …but never faster than this, so a one-minute session does not spend sixty entries
    /// on sixty pixels.
    private static let minimumProgressStep: TimeInterval = 5

    private let store: SharedStore

    init(store: SharedStore = .shared) {
        self.store = store
    }

    func placeholder(in context: Context) -> CadenceEntry {
        entry(at: Date(), records: records(now: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (CadenceEntry) -> Void) {
        let now = Date()
        completion(entry(at: now, records: records(now: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CadenceEntry>) -> Void) {
        let now = Date()
        let records = records(now: now)

        // `.after(endsAt)` while running, `.never` otherwise. The deadline is the one
        // instant at which the card's *composition* changes without anyone touching
        // it — the shell recolors, the transport becomes `Start another` / `+5`, and
        // the medium's pane swaps from `IN SESSION` to `SESSION COMPLETE`.
        guard records.state.effectiveStatus(now) == .running,
              let endsAt = records.state.endsAt,
              endsAt > now
        else {
            completion(Timeline(entries: [entry(at: now, records: records)], policy: .never))
            return
        }

        let entries = Self.progressDates(from: now, to: endsAt)
            .map { entry(at: $0, records: records) }

        completion(Timeline(entries: entries, policy: .after(endsAt)))
    }

    /// The instants the rule steps at, from `now` up to and including the deadline.
    ///
    /// Bounded two ways: never more than `maximumProgressEntries` steps, and never
    /// finer than `minimumProgressStep`. The deadline itself is always the last entry,
    /// so the card flips to its complete composition on time rather than waiting for
    /// the reload the policy asks for to actually be serviced.
    static func progressDates(from now: Date, to endsAt: Date) -> [Date] {
        let remaining = endsAt.timeIntervalSince(now)
        guard remaining > 0 else { return [now] }

        let step = max(minimumProgressStep, remaining / Double(maximumProgressEntries))
        var dates = [now]
        var next = now.addingTimeInterval(step)
        while next < endsAt {
            dates.append(next)
            next = next.addingTimeInterval(step)
        }
        dates.append(endsAt)
        return dates
    }

    /// One read of all four records, at one instant, so the tile and the pane cannot
    /// disagree about what time it is — and so a series of entries costs one read
    /// rather than one per entry.
    private func records(now: Date) -> Records {
        let snapshot = store.loadCalendarSnapshot(now: now)
        return Records(
            state: store.loadSessionState(now: now),
            snapshot: snapshot,
            dismissed: store.loadDismissedEvents(now: now).keys,
            preferences: store.loadPreferences()
        )
    }

    private struct Records {
        let state: SessionState
        let snapshot: CalendarSnapshot?
        let dismissed: Set<String>
        let preferences: Preferences
    }

    /// The card as it reads at `date`. `date` is not necessarily now: it is the instant
    /// this entry stands for, which for a running session is somewhere between the
    /// press and the deadline.
    private func entry(at date: Date, records: Records) -> CadenceEntry {
        CadenceEntry(
            date: date,
            tile: WidgetPresentation.tile(
                for: records.state,
                suggestion: CalendarDerivations.suggestedEvent(
                    in: records.snapshot,
                    dismissed: records.dismissed,
                    buffer: records.preferences.endEarlyBuffer,
                    now: date
                ),
                now: date
            ),
            pane: WidgetPresentation.pane(
                for: records.state,
                snapshot: records.snapshot,
                dismissed: records.dismissed,
                preferences: records.preferences,
                now: date
            )
        )
    }
}

struct CadenceWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var entry: CadenceEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(tile: entry.tile, pane: entry.pane)
        default:
            SmallWidgetView(tile: entry.tile)
        }
    }
}

struct CadenceWidget: Widget {
    let kind = "CadenceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CadenceProvider()) { entry in
            CadenceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Cadence")
        .description("Your current session, and what to start next.")
        .supportedFamilies([.systemSmall, .systemMedium])
        // The card draws its own shell colour edge to edge; the system's default
        // padding would inset it inside a lighter margin.
        .contentMarginsDisabled()
    }
}
