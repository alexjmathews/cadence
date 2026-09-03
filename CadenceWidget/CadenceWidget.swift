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
/// It schedules exactly one refresh, at the deadline. There is no periodic reload
/// and no ticker (D1 is the menu bar's problem): the running countdown is a
/// `Text(timerInterval:)` that SwiftUI advances itself, and every other state is a
/// still that only a *write* can change — and a write reloads every timeline through
/// `SharedStore` on its way past.
struct CadenceProvider: TimelineProvider {
    private let store: SharedStore

    init(store: SharedStore = .shared) {
        self.store = store
    }

    func placeholder(in context: Context) -> CadenceEntry {
        entry(now: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CadenceEntry) -> Void) {
        completion(entry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CadenceEntry>) -> Void) {
        let now = Date()
        let state = store.loadSessionState(now: now)

        // `.after(endsAt)` while running, `.never` otherwise. The deadline is the one
        // instant at which the card's *composition* changes without anyone touching
        // it — the shell recolors, the transport becomes `Start another` / `+5`, and
        // the medium's pane swaps from `IN SESSION` to `SESSION COMPLETE`. Every
        // other change arrives with a write.
        let policy: TimelineReloadPolicy =
            if state.effectiveStatus(now) == .running, let endsAt = state.endsAt {
                .after(endsAt)
            } else {
                .never
            }

        completion(Timeline(entries: [entry(now: now, state: state)], policy: policy))
    }

    /// One read of all four records, at one instant, so the tile and the pane cannot
    /// disagree about what time it is.
    private func entry(now: Date, state: SessionState? = nil) -> CadenceEntry {
        let state = state ?? store.loadSessionState(now: now)
        let snapshot = store.loadCalendarSnapshot(now: now)
        let dismissed = store.loadDismissedEvents(now: now).keys
        let preferences = store.loadPreferences()

        return CadenceEntry(
            date: now,
            tile: WidgetPresentation.tile(
                for: state,
                suggestion: CalendarDerivations.suggestedEvent(
                    in: snapshot,
                    dismissed: dismissed,
                    buffer: preferences.endEarlyBuffer,
                    now: now
                ),
                now: now
            ),
            pane: WidgetPresentation.pane(
                for: state,
                snapshot: snapshot,
                dismissed: dismissed,
                preferences: preferences,
                now: now
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
