import WidgetKit
import SwiftUI
import AppIntents

struct CadenceEntry: TimelineEntry {
    let date: Date
    let state: CadenceSessionState
}

/// Reads the shared session state from the App Group. When a session is active
/// the view shows a self-updating countdown, so we only need to schedule a
/// single refresh for when the session ends.
struct CadenceProvider: TimelineProvider {
    func placeholder(in context: Context) -> CadenceEntry {
        CadenceEntry(date: Date(), state: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (CadenceEntry) -> Void) {
        let state = context.isPreview ? .sample : SharedStore.load()
        completion(CadenceEntry(date: Date(), state: state))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CadenceEntry>) -> Void) {
        let now = Date()
        let state = SharedStore.load()
        let entry = CadenceEntry(date: now, state: state)

        let policy: TimelineReloadPolicy
        if let end = state.endDate, end > now {
            policy = .after(end)
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
            Image(systemName: entry.state.symbol)
                .font(.title2)
            Text(entry.state.title)
                .font(.headline)

            if let end = entry.state.endDate, end > entry.date {
                Text(timerInterval: entry.date...end, countsDown: true)
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
            } else {
                Text("No session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Interactive button — runs SendNotificationIntent in the widget
            // extension's background process, no app launch required.
            Button(intent: SendNotificationIntent()) {
                Label("Notify", systemImage: "bell.badge")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct CadenceWidget: Widget {
    let kind = "CadenceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CadenceProvider()) { entry in
            CadenceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Cadence")
        .description("Your current pomodoro session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
