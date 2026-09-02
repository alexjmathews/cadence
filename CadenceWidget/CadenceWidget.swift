import WidgetKit
import SwiftUI

struct CadenceEntry: TimelineEntry {
    let date: Date
    let state: SessionState
}

/// Reads the session from the App Group and renders a self-updating countdown, so
/// the only refresh worth scheduling is the one at the deadline. The widget stage
/// replaces this with the two real families and their intents.
struct CadenceProvider: TimelineProvider {
    func placeholder(in context: Context) -> CadenceEntry {
        CadenceEntry(date: Date(), state: SessionState())
    }

    func getSnapshot(in context: Context, completion: @escaping (CadenceEntry) -> Void) {
        let now = Date()
        completion(CadenceEntry(date: now, state: SharedStore.shared.loadSessionState(now: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CadenceEntry>) -> Void) {
        let now = Date()
        let state = SharedStore.shared.loadSessionState(now: now)
        let entry = CadenceEntry(date: now, state: state)

        let policy: TimelineReloadPolicy
        if state.effectiveStatus(now) == .running, let endsAt = state.endsAt {
            policy = .after(endsAt)
        } else {
            policy = .never
        }
        completion(Timeline(entries: [entry], policy: policy))
    }
}

struct CadenceWidgetEntryView: View {
    var entry: CadenceEntry

    var body: some View {
        VStack(spacing: 6) {
            Text(entry.state.displayName)
                .font(DesignTokens.Typography.stripEventTitle)

            if entry.state.effectiveStatus(entry.date) == .running, let endsAt = entry.state.endsAt {
                Text(timerInterval: entry.date...endsAt, countsDown: true)
                    .font(DesignTokens.Typography.widgetNumerals)
            } else {
                Text(entry.state.effectiveStatus(entry.date) == .complete ? "Complete" : "No session")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.TextColor.secondary)
            }
        }
        .containerBackground(DesignTokens.Surface.base, for: .widget)
    }
}

struct CadenceWidget: Widget {
    let kind = "CadenceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CadenceProvider()) { entry in
            CadenceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Cadence")
        .description("Your current session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
