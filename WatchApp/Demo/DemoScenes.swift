import CoreLocation
import SwiftUI

/// Screenshot scenes for `-demo` launches: the real start screen (with
/// demo shoes seeded through WatchSync), a mid-run metrics tableau, the
/// upcoming-fork pop-up, and the km-split pop-up — one perfect frame
/// per feature. Nothing here touches HealthKit, the route store, or
/// sync.
struct DemoRootView: View {
    let workout: WorkoutManager
    let sync: WatchSync

    var body: some View {
        TabView {
            StartView(workout: workout, sync: sync)
            DemoMetricsScene()
            DemoForkScene()
            DemoSplitScene()
        }
        .tabViewStyle(.page)
    }
}

/// The fork pop-up as it fires ~100 m out: two known ways on, each with
/// its stretch, the pace to beat, and the quickest way home — plus the
/// live segment delta pushing you to the fork.
struct DemoForkScene: View {
    var body: some View {
        EventOverlay(
            overlay: .fork(
                RoutePrediction(
                    nodeKey: RouteGraph.GridKey(x: 0, y: 0),
                    choices: [
                        RoutePrediction.Choice(
                            id: 0, direction: .left, distanceMeters: 1_240,
                            bestPaceSecondsPerKm: 342, homeSeconds: 23 * 60,
                            probabilityPercent: 70, sampleCount: 14
                        ),
                        RoutePrediction.Choice(
                            id: 1, direction: .right, distanceMeters: 830,
                            bestPaceSecondsPerKm: 371, homeSeconds: 41 * 60,
                            probabilityPercent: 30, sampleCount: 6
                        ),
                    ]
                ),
                segmentDelta: -4
            ),
            onTap: {}
        )
    }
}

/// A composed mid-run moment: 4.2 km in, up on the current segment.
struct DemoMetricsScene: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(ActivityMode.running.label, systemImage: ActivityMode.running.symbolName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                }

                Text(Format.duration(1_572))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(.yellow)

                demoMetricRow(value: Format.pace(334), unit: "/km", icon: "speedometer")
                demoMetricRow(value: Format.distance(4_210), unit: "", icon: "point.topleft.down.curvedto.point.bottomright.up")
                demoMetricRow(value: "152", unit: "bpm", icon: "heart.fill", iconColor: .red)

                SegmentStatusRow(toGoMeters: 640, deltaSeconds: -4)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 4)
        }
    }

    private func demoMetricRow(value: String, unit: String, icon: String, iconColor: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(iconColor)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
            if !unit.isEmpty {
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The km-split pop-up, frozen at its best moment.
struct DemoSplitScene: View {
    var body: some View {
        EventOverlay(
            overlay: .split(KmSplit(kilometre: 4, seconds: 328, historyDeltaSeconds: -7, at: Date())),
            onTap: {}
        )
    }
}
