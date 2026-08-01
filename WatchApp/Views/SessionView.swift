import SwiftUI

/// What can take over the screen mid-run. Field-tested rule: anything
/// worth telling a runner is worth telling them in huge type.
enum SessionOverlay {
    case split(KmSplit)
    case fork(RoutePrediction, segmentDelta: TimeInterval?)
    case turn(PlanTurn)
    case segment(SegmentComparison)
}

/// The in-workout screens: controls, big live metrics, and a forks page
/// — with full-screen pop-ups for splits, upcoming forks and segment
/// results (auto-dismiss after a few seconds, tap to dismiss).
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
                ForksView(workout: workout)
                    .tag(2)
            }
            .tabViewStyle(.page)

            if let overlay {
                EventOverlay(overlay: overlay) {
                    if case .fork = overlay {
                        selectedTab = 2
                    }
                    dismiss()
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        // Registration order matters when events coincide (a segment
        // completes just as the next fork appears): later wins, and the
        // fork is the actionable one.
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
        .onChange(of: workout.routePrediction?.nodeKey) { _, nodeKey in
            if nodeKey != nil, let prediction = workout.routePrediction {
                show(.fork(prediction, segmentDelta: workout.segmentLiveDeltaSeconds), for: 8)
            }
        }
        .onChange(of: workout.planTurn?.nodeKey) { _, nodeKey in
            if nodeKey != nil, let turn = workout.planTurn {
                show(.turn(turn), for: 8)
            }
        }
    }

    private func show(_ newOverlay: SessionOverlay, for seconds: TimeInterval) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
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
                    .foregroundStyle(Gaitway.cyan)
                Text(Format.duration(split.seconds))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .gaitwayShimmer()
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
        case .fork(let prediction, let segmentDelta):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 6) {
                        AnimatedForkMark()
                        Text("FORK")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Gaitway.magenta)
                    }
                    Spacer()
                    if let segmentDelta {
                        SegmentDeltaChip(deltaSeconds: segmentDelta)
                    }
                }
                ForEach(prediction.choices.prefix(2)) { choice in
                    ForkChoiceRow(choice: choice)
                }
                if prediction.choices.count > 2 {
                    Text("more on the forks page →")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        case .turn(let turn):
            VStack(spacing: 4) {
                Label("ROUTE", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Gaitway.cyan)
                if let direction = turn.direction {
                    Image(systemName: direction.symbolName)
                        .font(.system(size: 52, weight: .bold))
                    Text(direction.label)
                        .font(.title3.weight(.semibold))
                    if let meters = turn.nextLegMeters {
                        Text("\(Format.compactDistance(meters)) segment")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 52, weight: .bold))
                    Text("Route ends here")
                        .font(.title3.weight(.semibold))
                }
            }
        case .segment(let comparison):
            VStack(spacing: 2) {
                Label("SEGMENT", systemImage: "flag.checkered")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Gaitway.cyan)
                Text(Format.duration(comparison.seconds))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .gaitwayShimmer()
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
                        .foregroundStyle(workout.mode == .running ? Gaitway.magenta : Gaitway.cyan)
                    Spacer()
                    if workout.isAutoPaused {
                        Text("PAUSED")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.yellow)
                    }
                }

                if let home = workout.homeGuidance {
                    HomePanel(guidance: home)
                }

                Text(Format.duration(workout.elapsed))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(Gaitway.gradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .gaitwayShimmer(period: 4.5)

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

                if workout.segmentToGoMeters != nil || workout.segmentLiveDeltaSeconds != nil {
                    SegmentStatusRow(
                        toGoMeters: workout.segmentToGoMeters,
                        deltaSeconds: workout.segmentLiveDeltaSeconds,
                        progress: workout.segmentProgressFraction
                    )
                }
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

// MARK: - Forks page

/// The dedicated page for route intelligence. Free running: the fork
/// ahead in full, readable type — each branch's stretch, the pace to
/// beat on it, and the quickest way home that way. Following a planned
/// route: only the planned turn, with distance to go and the overall ±.
struct ForksView: View {
    let workout: WorkoutManager

    var body: some View {
        ScrollView {
            if workout.activePlan != nil {
                planContent
            } else {
                forksContent
            }
        }
    }

    private var planContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond")
                .font(.body.weight(.semibold))
                .foregroundStyle(Gaitway.cyan)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.body)
                        .foregroundStyle(Gaitway.cyan)
                    if let toGo = workout.planDistanceToGoMeters {
                        Text("\(Format.compactDistance(toGo)) to go")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    if let delta = workout.overallDeltaSeconds {
                        SegmentDeltaChip(deltaSeconds: delta)
                    }
                }
                // The route as a line you travel: filled behind you,
                // forks as ticks, your position glowing.
                if let progress = workout.planProgressFraction {
                    PathTravelTrack(stops: workout.planForkFractions, progress: progress)
                }
            }
            .padding(7)
            .background(Gaitway.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            if let turn = workout.planTurn {
                HStack(spacing: 10) {
                    Image(systemName: turn.direction?.symbolName ?? "flag.checkered")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Gaitway.cyan)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(turn.direction?.label ?? "Route ends")
                            .font(.title3.weight(.bold))
                        if let meters = turn.nextLegMeters {
                            Text("\(Format.compactDistance(meters)) segment")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(6)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Text("Follow the route — the turn shows ~100 m before each fork.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let home = workout.homeGuidance {
                HomePanel(guidance: home)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
    }

    private var forksContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                AnimatedForkMark(size: 15)
                Text("Forks")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Gaitway.magenta)
            }

            if workout.segmentToGoMeters != nil || workout.segmentLiveDeltaSeconds != nil {
                SegmentStatusRow(
                    toGoMeters: workout.segmentToGoMeters,
                    deltaSeconds: workout.segmentLiveDeltaSeconds,
                    progress: workout.segmentProgressFraction
                )
            }

            if let prediction = workout.routePrediction {
                ForEach(prediction.choices) { choice in
                    ForkChoiceRow(choice: choice)
                }
            } else {
                Text("No fork ahead")
                    .font(.title3.weight(.semibold))
                Text("Choices appear ~100 m before a junction you've run before.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let home = workout.homeGuidance {
                HomePanel(guidance: home)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
    }
}

/// The segment being run, in one row: distance left of it (when its
/// length is known from history) and the live vs-history delta. Shared
/// by the metrics page and the forks page.
struct SegmentStatusRow: View {
    let toGoMeters: Double?
    let deltaSeconds: TimeInterval?
    /// How far through the segment you are, for the travel track.
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .font(.body)
                    .foregroundStyle(Gaitway.magenta)
                if let toGoMeters {
                    Text("\(Format.compactDistance(toGoMeters)) to go")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("Segment")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let deltaSeconds {
                    SegmentDeltaChip(deltaSeconds: deltaSeconds)
                }
            }
            if let progress {
                PathTravelTrack(progress: progress)
            }
        }
        .padding(7)
        .background(Gaitway.magenta.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Live vs-history delta for the segment being run — green means ahead
/// of your usual self over this exact ground.
struct SegmentDeltaChip: View {
    let deltaSeconds: TimeInterval

    var body: some View {
        Text(Format.signedDuration(deltaSeconds))
            .font(.system(.body, design: .rounded).weight(.bold))
            .foregroundStyle(deltaSeconds <= 0 ? .green : .red)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                (deltaSeconds <= 0 ? Color.green : .red).opacity(0.18),
                in: Capsule()
            )
    }
}

/// One branch, in type you can read at pace: direction, the stretch's
/// length, the pace to beat on it, and the quickest time home that way.
struct ForkChoiceRow: View {
    let choice: RoutePrediction.Choice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: choice.direction.symbolName)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Gaitway.magenta)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 0) {
                // Field-tested on the 49mm: full-precision distances
                // truncated ("1.24… beat 5'…"), so compact units and
                // scale-to-fit.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let meters = choice.distanceMeters {
                        Text(Format.compactDistance(meters))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                    }
                    if let pace = choice.bestPaceSecondsPerKm {
                        Text("beat \(Format.pace(pace))")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(Gaitway.cyan)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text(secondLine)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .padding(6)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var secondLine: String {
        var parts: [String] = []
        if let homeSeconds = choice.homeSeconds {
            parts.append("home \(max(1, Int((homeSeconds / 60).rounded())))m")
        }
        parts.append("\(choice.probabilityPercent)%")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Persistent panels — body-size minimum

/// Take-me-home guidance: at a known fork, the first turn of the fastest
/// known way back plus its ETA; between forks, a plain arrow toward the
/// usual finish.
struct HomePanel: View {
    let guidance: HomeGuidance

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "house.fill")
                .font(.body)
                .foregroundStyle(Gaitway.cyan)
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
        .background(Gaitway.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
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

            if workout.activePlan != nil {
                Button {
                    workout.stopFollowingPlan()
                } label: {
                    Label("Stop route", systemImage: "xmark.diamond")
                }
                .tint(Gaitway.cyan)
            }

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
