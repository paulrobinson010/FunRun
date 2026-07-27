import SwiftUI
import WidgetKit

/// Watch-face complication: this week's distance at a glance, and a
/// one-tap way into the app to start a run. Reads the figure the app
/// publishes to the shared app group after every session.
@main
struct FunRunWidgets: WidgetBundle {
    var body: some Widget {
        WeekDistanceComplication()
    }
}

struct WeekDistanceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekDistance", provider: WeekProvider()) { entry in
            WeekDistanceView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("FunRun")
        .description("This week's distance. Tap to start a run.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct WeekEntry: TimelineEntry {
    let date: Date
    let weekMeters: Double
}

struct WeekProvider: TimelineProvider {
    private static let appGroupID = "group.com.paulrobinson.FunRun"
    private static let weekMetersKey = "weekMeters"

    private func currentEntry() -> WeekEntry {
        let meters = UserDefaults(suiteName: Self.appGroupID)?
            .double(forKey: Self.weekMetersKey) ?? 0
        return WeekEntry(date: Date(), weekMeters: meters)
    }

    func placeholder(in context: Context) -> WeekEntry {
        WeekEntry(date: Date(), weekMeters: 12_300)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        // The app reloads timelines after each run; the periodic refresh
        // only exists to roll the figure over at the start of a new week.
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }
}

struct WeekDistanceView: View {
    let entry: WeekEntry

    @Environment(\.widgetFamily) private var family

    private var km: String {
        String(format: entry.weekMeters >= 100_000 ? "%.0f" : "%.1f", entry.weekMeters / 1000)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("FunRun \(km) km this week")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("FunRun", systemImage: "figure.run")
                    .font(.headline)
                Text("\(km) km this week")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        default:
            VStack(spacing: 0) {
                Image(systemName: "figure.run")
                    .font(.headline)
                Text(km)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                Text("km")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
