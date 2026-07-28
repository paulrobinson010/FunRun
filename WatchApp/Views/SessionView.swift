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
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
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

                if let split = workout.kmSplit {
                    KmSplitBanner(split: split)
                }

                if let ghost = workout.ghostStatus {
                    GhostPanel(status: ghost)
                }

                if let home = workout.homeGuidance {
                    HomePanel(guidance: home)
                }

                if let comparison = workout.segmentComparison {
                    SegmentComparisonBanner(comparison: comparison)
                }

                if let prediction = workout.routePrediction {
                    RoutePredictionPanel(prediction: prediction)
                }

                Text(Format.duration(workout.elapsed))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

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
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 4)
            .opacity(workout.isAutoPaused ? 0.6 : 1)
        }
    }

    private func metricRow(value: String, unit: String, icon: String, iconColor: Color = .secondary) -> some View {
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

/// Shown at a known decision point: one row per way you've gone before —
/// expected time to finish, expected session-total calories, and how
/// often you've picked it.
struct RoutePredictionPanel: View {
    let prediction: RoutePrediction

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(prediction.choices.prefix(3)) { choice in
                HStack(spacing: 5) {
                    Image(systemName: choice.direction.symbolName)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(choice.isRecommended ? .green : .orange)
                        .frame(width: 16)
                    Text("\(choice.finishInMinutes)m")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                    Text("\(choice.totalCalories) cal")
                        .font(.system(.footnote, design: .rounded))
                    Spacer()
                    if choice.isRecommended {
                        Image(systemName: "target")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    Text("\(choice.probabilityPercent)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 3)
                .background(
                    choice.isRecommended ? AnyShapeStyle(.green.opacity(0.2)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 5)
                )
            }

            if prediction.choices.contains(where: { $0.nextForkSeconds != nil }) {
                HStack(spacing: 6) {
                    Text("next fork")
                        .foregroundStyle(.secondary)
                    ForEach(prediction.choices.prefix(3)) { choice in
                        if let seconds = choice.nextForkSeconds {
                            HStack(spacing: 1) {
                                Image(systemName: choice.direction.symbolName)
                                Text(Format.duration(seconds))
                            }
                        }
                    }
                }
                .font(.caption2)
            }
        }
        .padding(6)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Flashes at each kilometre: the split's moving time and its delta to
/// the previous kilometre — quicker in green, slower in red.
struct KmSplitBanner: View {
    let split: KmSplit

    var body: some View {
        HStack(spacing: 5) {
            Text("KM \(split.kilometre)")
                .font(.footnote.weight(.bold))
            Text(Format.duration(split.seconds))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
            Spacer()
            if let delta = split.deltaToPrevious {
                Text(Format.signedDuration(delta))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(delta <= 0 ? .green : .red)
            }
        }
        .padding(6)
        .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The ghost race line: on route it shows the upcoming turn, whether
/// you're ahead (green) or behind (red) the ghost at this exact spot,
/// and the route distance left. Off route it becomes the way back.
struct GhostPanel: View {
    let status: GhostStatus

    var body: some View {
        HStack(spacing: 5) {
            switch status.state {
            case .onRoute:
                Image(systemName: "figure.run.circle")
                    .font(.footnote)
                    .foregroundStyle(.purple)
                if let turn = status.turn {
                    Image(systemName: turn.symbolName)
                        .font(.footnote.weight(.bold))
                }
                Text(Format.signedDuration(status.deltaSeconds))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(status.deltaSeconds >= 0 ? .green : .red)
                Spacer()
                Text(Format.distance(status.remainingMeters))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .offRoute:
                Image(systemName: "location.slash")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Text("Off route")
                    .font(.footnote.weight(.semibold))
                Spacer()
                if let direction = status.directionToRoute {
                    Image(systemName: direction.symbolName)
                        .font(.footnote.weight(.bold))
                }
                if let meters = status.metersToRoute {
                    Text("\(Int(meters.rounded())) m")
                        .font(.footnote)
                }
            case .finished:
                Image(systemName: "figure.run.circle")
                    .font(.footnote)
                    .foregroundStyle(.purple)
                Text(status.deltaSeconds >= 0 ? "Ghost beaten" : "Ghost won")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(Format.signedDuration(status.deltaSeconds))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(status.deltaSeconds >= 0 ? .green : .red)
            }
        }
        .padding(6)
        .background(.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Take-me-home guidance: at a known fork, the first turn of the fastest
/// known way back plus its ETA; between forks, a plain arrow toward the
/// usual finish.
struct HomePanel: View {
    let guidance: HomeGuidance

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "house.fill")
                .font(.footnote)
                .foregroundStyle(.cyan)
            Image(systemName: guidance.direction.symbolName)
                .font(.footnote.weight(.bold))
            if let minutes = guidance.etaMinutes {
                Text("\(minutes)m home")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
            } else {
                Text("towards home")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(6)
        .background(.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Flashes up when a segment between two forks completes: this pass's
/// time, the delta against the 28-day typical for the stretch, and a
/// medal when it beat every recent pass.
struct SegmentComparisonBanner: View {
    let comparison: SegmentComparison

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.checkered")
                .font(.footnote)
            Text(Format.duration(comparison.seconds))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
            if let delta = comparison.deltaSeconds {
                Text(Format.signedDuration(delta))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(delta <= 0 ? .green : .red)
            } else {
                Text("no recent history")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if comparison.isBest {
                Image(systemName: "medal.fill")
                    .font(.footnote)
                    .foregroundStyle(.yellow)
            } else if comparison.sampleCount > 0 {
                Text("×\(comparison.sampleCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
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

            Button {
                workout.toggleHomeGuidance()
            } label: {
                Label(
                    workout.homeGuidanceEnabled ? "Guiding home" : "Take me home",
                    systemImage: "house.fill"
                )
            }
            .tint(workout.homeGuidanceEnabled ? .cyan : nil)

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
