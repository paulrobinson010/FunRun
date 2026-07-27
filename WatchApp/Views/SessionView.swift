import SwiftUI

/// The in-workout screens: swipe between controls and live metrics,
/// metrics front and centre by default.
struct SessionView: View {
    let workout: WorkoutManager

    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            ControlsView(workout: workout)
                .tag(0)
            MetricsView(workout: workout)
                .tag(1)
        }
        .tabViewStyle(.page)
    }
}

/// Current pace, distance so far, heart rate — plus what the app currently
/// thinks you're doing and whether it has auto-paused.
struct MetricsView: View {
    let workout: WorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(workout.mode.label, systemImage: workout.mode.symbolName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(workout.mode == .running ? .green : .cyan)
                Spacer()
                if workout.isAutoPaused {
                    Text("PAUSED")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.yellow)
                }
            }

            Text(Format.duration(workout.elapsed))
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(.yellow)

            metricRow(
                value: Format.pace(workout.currentPaceSecondsPerKm),
                unit: "/km",
                icon: "speedometer"
            )
            metricRow(
                value: Format.distance(workout.distanceMeters),
                unit: "",
                icon: "point.topleft.down.curvedto.point.bottomright.up"
            )
            metricRow(
                value: Format.heartRate(workout.heartRate),
                unit: "bpm",
                icon: "heart.fill",
                iconColor: .red
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
        .opacity(workout.isAutoPaused ? 0.6 : 1)
    }

    private func metricRow(value: String, unit: String, icon: String, iconColor: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(iconColor)
                .frame(width: 18)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.medium))
            if !unit.isEmpty {
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ControlsView: View {
    let workout: WorkoutManager

    var body: some View {
        VStack(spacing: 12) {
            Button {
                workout.end()
            } label: {
                Label("End", systemImage: "xmark")
            }
            .tint(.red)

            Button {
                workout.togglePause()
            } label: {
                if workout.phase.isPaused {
                    Label("Resume", systemImage: "play.fill")
                } else {
                    Label("Pause", systemImage: "pause.fill")
                }
            }
            .tint(.yellow)

            if let shoe = workout.shoe {
                Label(shoe.displayName, systemImage: "shoe.2")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
    }
}
