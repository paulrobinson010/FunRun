import CoreLocation
import SwiftUI

/// Screenshot scenes for `-demo` launches: the real start screen (with
/// demo shoes seeded through WatchSync), a mid-run metrics tableau, and
/// the km-split pop-up — one perfect frame per feature. Nothing here
/// touches HealthKit, the route store, or sync.
struct DemoRootView: View {
    let workout: WorkoutManager
    let sync: WatchSync

    var body: some View {
        TabView {
            StartView(workout: workout, sync: sync)
            DemoMetricsScene()
            DemoSplitScene()
        }
        .tabViewStyle(.page)
    }
}

/// A composed mid-run moment: 4.2 km in, ahead of the ghost.
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

                GhostPanel(status: GhostStatus(
                    state: .onRoute, deltaSeconds: 15, remainingMeters: 2_300,
                    turn: .straight, directionToRoute: nil, metersToRoute: nil
                ))

                Text(Format.duration(1_572))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(.yellow)

                demoMetricRow(value: Format.pace(334), unit: "/km", icon: "speedometer")
                demoMetricRow(value: Format.distance(4_210), unit: "", icon: "point.topleft.down.curvedto.point.bottomright.up")
                demoMetricRow(value: "152", unit: "bpm", icon: "heart.fill", iconColor: .red)
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
