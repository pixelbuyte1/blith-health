import BlithCore
import SwiftUI
import WidgetKit

struct BlithEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Reads what the app last wrote. The app reloads timelines after every sync; the provider adds a
/// midnight entry so yesterday's numbers are never shown as today's.
struct BlithProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlithEntry {
        BlithEntry(date: Date(), snapshot: .preview())
    }

    func getSnapshot(in context: Context, completion: @escaping (BlithEntry) -> Void) {
        completion(BlithEntry(date: Date(), snapshot: context.isPreview ? (WidgetStore.load() ?? .preview()) : WidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BlithEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetStore.load()
        var entries = [BlithEntry(date: now, snapshot: snapshot)]
        let calendar = Calendar.current
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(BlithEntry(date: midnight, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

struct ReadinessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.widgetKind, provider: BlithProvider()) { entry in
            ReadinessEntryView(entry: entry)
        }
        .configurationDisplayName("Readiness")
        .description("Today's readiness, sleep and load, measured against your own usual range.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct MovementWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.movementKind, provider: BlithProvider()) { entry in
            MovementEntryView(entry: entry)
        }
        .configurationDisplayName("Steps")
        .description("Today's steps against a usual day at the same hour.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct ReadinessEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BlithEntry
    var body: some View {
        ReadinessWidgetView(snapshot: entry.snapshot, date: entry.date, family: family)
            .containerBackground(for: .widget) { WidgetBackdrop() }
    }
}

struct MovementEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BlithEntry
    var body: some View {
        MovementWidgetView(snapshot: entry.snapshot, date: entry.date, family: family)
            .containerBackground(for: .widget) { WidgetBackdrop() }
    }
}

@main
struct BlithWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadinessWidget()
        MovementWidget()
    }
}
