import SwiftUI

/// What can take over the screen mid-run. Field-tested rule: anything
/// worth telling a runner is worth telling them in huge type.
enum SessionOverlay {
    case split(KmSplit)
    case segment(SegmentComparison)
}

/// The in-workout screens: controls and big live metrics — with
/// full-screen pop-ups for splits and segment results (auto-dismiss
/// after a few seconds, tap to dismiss).
struct SessionView: View {
    let workout: WorkoutManager

    @State private var selectedTab = 1
    @State private var overlay: SessionOverlay?
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ControlsView(workout: workout)
                    .tag(0)
                MetricsView(workout: workout)
                    .tag(1)
            }
            .tabViewStyle(.page)

            if let overlay {
                EventOverlay(overlay: overlay) {
                    dismiss()
                }
                .transition(.opacity)
            }
        }
        // Registration order matters when events coincide: later wins.
        .onChange(of: workout.segmentComparison) { _, comparison in
            if let comparison {
                show(.segment(comparison), for: 5)
            }
        }
        .onChange(of: workout.kmSplit) { _, split in
            if let split {
                show(.split(split), for: 5)
            }
        }
    }

    private func show(_ newOverlay: SessionOverlay, for seconds: TimeInterval) {
        withAnimation(.easeIn(duration: 0.15)) {
            overlay = newOverlay
        }
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                overlay = nil
            }
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            overlay = nil
        }
    }
}

// MARK: - Full-screen event pop-ups

/// Big-type takeover for a few seconds; tap anywhere to dismiss.
struct EventOverlay: View {
    let overlay: SessionOverlay
    let onTap: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            content
                .padding(.horizontal, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    @ViewBuilder
    private var content: some View {
        switch overlay {
        case .split(let split):
            VStack(spacing: 2) {
                Text("KM \(split.kilometre)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)
                Text(Format.duration(split.seconds))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                // vs your own recent history over the same ground;
                // stretches you've never run before contribute zero.
                if abs(split.historyDeltaSeconds) >= 1 {
                    Text(Format.signedDuration(split.historyDeltaSeconds))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(split.historyDeltaSeconds <= 0 ? .green : .red)
                } else {
                    Text("±0 vs your usual")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        case .segment(let comparison):
            VStack(spacing: 2) {
                Label("SEGMENT", systemImage: "flag.checkered")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.cyan)
                Text(Format.duration(comparison.seconds))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                if let delta = comparison.deltaSeconds {
                    Text(Format.signedDuration(delta))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(delta <= 0 ? .green : .red)
                }
                if comparison.isBest {
                    Label("Best in 28 days", systemImage: "medal.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }
        }
    }
}

// MARK: - Metrics (nothing smaller than the distance text)

struct MetricsView: View {
    let workout: WorkoutManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(workout.mode.label, systemImage: workout.mode.symbolName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(workout.mode == .running ? .green : .cyan)
                    Spacer()
                    if workout.isAutoPaused {
                        Text("PAUSED")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.yellow)
                    }
                }

                if let ghost = workout.ghostStatus {
                    GhostPanel(status: ghost)
                }

                if let home = workout.homeGuidance {
                    HomePanel(guidance: home)
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

// MARK: - Persistent panels (ghost, home) — body-size minimum

/// The ghost race line: on route it shows the upcoming turn, whether
/// you're ahead (green) or behind (red) the ghost at this exact spot,
/// and the route distance left. Off route it becomes the way back.
struct GhostPanel: View {
    let status: GhostStatus

    var body: some View {
        HStack(spacing: 6) {
            switch status.state {
            case .onRoute:
                Image(systemName: "figure.run.circle")
                    .font(.body)
                    .foregroundStyle(.purple)
                if let turn = status.turn {
                    Image(systemName: turn.symbolName)
                        .font(.title3.weight(.bold))
                }
                Text(Format.signedDuration(status.deltaSeconds))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(status.deltaSeconds >= 0 ? .green : .red)
                Spacer()
                Text(Format.distance(status.remainingMeters))
                    .font(.body)
                    .foregroundStyle(.secondary)
            case .offRoute:
                Image(systemName: "location.slash")
                    .font(.body)
                    .foregroundStyle(.red)
                Text("Off route")
                    .font(.title3.weight(.semibold))
                Spacer()
                if let direction = status.directionToRoute {
                    Image(systemName: direction.symbolName)
                        .font(.title3.weight(.bold))
                }
                if let meters = status.metersToRoute {
                    Text("\(Int(meters.rounded())) m")
                        .font(.body)
                }
            case .finished:
                Image(systemName: "figure.run.circle")
                    .font(.body)
                    .foregroundStyle(.purple)
                Text(status.deltaSeconds >= 0 ? "Ghost beaten" : "Ghost won")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(Format.signedDuration(status.deltaSeconds))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(status.deltaSeconds >= 0 ? .green : .red)
            }
        }
        .padding(7)
        .background(.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Take-me-home guidance: at a known fork, the first turn of the fastest
/// known way back plus its ETA; between forks, a plain arrow toward the
/// usual finish.
struct HomePanel: View {
    let guidance: HomeGuidance

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "house.fill")
                .font(.body)
                .foregroundStyle(.cyan)
            Image(systemName: guidance.direction.symbolName)
                .font(.title3.weight(.bold))
            if let minutes = guidance.etaMinutes {
                Text("\(minutes)m home")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
            } else {
                Text("towards home")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(7)
        .background(.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Controls

struct ControlsView: View {
    let workout: WorkoutManager

    var body: some View {
        VStack(spacing: 12) {
            Button {
                workout.end()
            } label: {
                if workout.phase == .ending {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Saving…")
                    }
                } else {
                    Label("End", systemImage: "xmark")
                }
            }
            .tint(.red)
            .disabled(workout.phase == .ending)

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
            .disabled(workout.phase == .ending)

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
