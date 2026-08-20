import WidgetKit
import SwiftUI

struct CadenceEntry: TimelineEntry {
    let date: Date
    let state: CadenceSessionState
}

/// Static provider for the shell. Once the App Group is wired, this will read
/// the real `CadenceSessionState` and build a countdown timeline.
struct CadenceProvider: TimelineProvider {
    func placeholder(in context: Context) -> CadenceEntry {
        CadenceEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CadenceEntry) -> Void) {
        completion(CadenceEntry(date: Date(), state: .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CadenceEntry>) -> Void) {
        let entry = CadenceEntry(date: Date(), state: .placeholder)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct CadenceWidgetEntryView: View {
    var entry: CadenceEntry

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.title2)
            Text("Cadence")
                .font(.headline)
            Text("No session")
                .font(.caption)
                .foregroundStyle(.secondary)
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
