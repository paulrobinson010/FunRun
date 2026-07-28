import CoreLocation
import SwiftUI

/// Screenshot scenes for `-demo` launches: page 1 is the real start
/// screen (with demo shoes seeded through WatchSync), page 2 is a frozen
/// mid-run tableau with every panel populated at once — a composition
/// that real runs rarely produce photogenically. Nothing here touches
/// HealthKit, the route store, or sync.
struct DemoRootView: View {
    let workout: WorkoutManager
    let sync: WatchSync

    var body: some View {
        TabView {
            StartView(workout: workout, sync: sync)
            DemoMetricsScene()
        }
        .tabViewStyle(.page)
    }
}

/// A composed mid-run moment: 4.2 km in, at a fork, ahead of the ghost,
/// just clocked a quick kilometre.
struct DemoMetricsScene: View {
    private var prediction: RoutePrediction {
        let node = RouteGraph.GridKey(CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1657))
        return RoutePrediction(nodeKey: node, choices: [
            RoutePrediction.Choice(
                id: 0, direction: .left, finishInMinutes: 25, totalCalories: 548,
                probabilityPercent: 70, sampleCount: 14, nextForkSeconds: 250, isRecommended: true
            ),
            RoutePrediction.Choice(
                id: 1, direction: .right, finishInMinutes: 44, totalCalories: 802,
                probabilityPercent: 30, sampleCount: 6, nextForkSeconds: 385
            ),
        ])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label(ActivityMode.running.label, systemImage: ActivityMode.running.symbolName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                }

                KmSplitBanner(split: KmSplit(
                    kilometre: 4, seconds: 328, deltaToPrevious: -7, at: Date()
                ))

                GhostPanel(status: GhostStatus(
                    state: .onRoute, deltaSeconds: 15, remainingMeters: 2_300,
                    turn: .straight, directionToRoute: nil, metersToRoute: nil
                ))

                RoutePredictionPanel(prediction: prediction)

                Text(Format.duration(1_572))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !unit.isEmpty {
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
