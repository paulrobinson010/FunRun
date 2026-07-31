import SwiftUI
import UIKit
import WidgetKit

/// Watch-face complication: the Gaitway logo as a one-tap way into the
/// app to start a run. No numbers — the launcher is the job.
@main
struct FunRunWidgets: WidgetBundle {
    var body: some Widget {
        WeekDistanceComplication()
    }
}

struct WeekDistanceComplication: Widget {
    var body: some WidgetConfiguration {
        // The kind string predates the logo-only design; changing it
        // would drop the complication off existing watch faces.
        StaticConfiguration(kind: "WeekDistance", provider: WeekProvider()) { entry in
            WeekDistanceView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Gaitway")
        .description("Tap to start a run.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct WeekEntry: TimelineEntry {
    let date: Date
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        WeekEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(WeekEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        // Static artwork, but a slow periodic refresh means a future
        // build's artwork reaches the face without re-adding the
        // complication.
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
        completion(Timeline(entries: [WeekEntry(date: Date())], policy: .after(next)))
    }
}

struct WeekDistanceView: View {
    let entry: WeekEntry

    @Environment(\.widgetFamily) private var family

    /// The glyph cut of the logo: neon runner on transparency (the full
    /// square logo is ~80% black and reads as a black blob at this
    /// size). Loaded defensively: if the asset ever fails to resolve in
    /// the extension bundle, a runner symbol shows instead of nothing —
    /// so a missing icon looks different from a dead widget.
    private var icon: some View {
        Group {
            if let glyph = UIImage(named: "LogoGlyph") {
                Image(uiImage: glyph)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "figure.run")
                    .resizable()
                    .scaledToFit()
                    .padding(2)
                    .foregroundStyle(.cyan)
            }
        }
        .widgetAccentable()
    }

    // Unredacted throughout: a logo isn't sensitive, and it guarantees
    // real content renders even if the face never promotes past the
    // placeholder state.
    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Gaitway")
                .unredacted()
        case .accessoryRectangular:
            HStack(spacing: 6) {
                icon
                    .frame(width: 30, height: 30)
                Text("Gaitway")
                    .font(.headline)
                Spacer(minLength: 0)
            }
            .unredacted()
        default:
            ZStack {
                AccessoryWidgetBackground()
                icon
                    .padding(5)
            }
            .unredacted()
        }
    }
}
