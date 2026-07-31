import CoreLocation
import MapKit
import SwiftUI

/// Build a route over everything the watch has learned: start at home,
/// pick a coloured segment to extend the route, repeat until it's the
/// run you want, then send it to the watch — the next workout follows
/// it turn by turn.
struct RoutePlannerView: View {
    let model: AppModel

    @State private var planner = RoutePlanModel()
    @State private var position: MapCameraPosition = .automatic
    @State private var sentPlanSummary: String? = UserDefaults.standard.string(forKey: Self.sentPlanKey)

    static let sentPlanKey = "sentPlanSummary"

    private static let palette: [Color] = [
        .cyan, .pink, .orange, .green, .purple, .yellow, .blue, .mint, .red, .indigo,
    ]

    var body: some View {
        NavigationStack {
            Group {
                if planner.loading {
                    ProgressView("Reading your runs…")
                } else if planner.network == nil || planner.startNode == nil {
                    ContentUnavailableView(
                        "No network yet",
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                        description: Text("Run with the watch a few times and you can plan routes over your own network here.")
                    )
                } else {
                    plannerContent
                }
            }
            .navigationTitle("Route")
            .toolbar {
                if !planner.legs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Undo", systemImage: "arrow.uturn.backward") {
                            planner.undo()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Reset", role: .destructive) {
                            planner.reset()
                        }
                    }
                }
            }
            .task(id: model.routeBackup.entries.count) {
                let runs: [RouteRun]
                if DemoMode.isActive {
                    runs = DemoData.runs.compactMap { summary in
                        guard let track = summary.track else { return nil }
                        return RouteRun(
                            id: summary.id,
                            date: summary.startDate,
                            totalSeconds: summary.activeSeconds,
                            totalEnergyKilocalories: 0,
                            points: track
                        )
                    }
                } else {
                    runs = await Task.detached(priority: .userInitiated) {
                        RouteBackupStore.loadAllRuns()
                    }.value
                }
                planner.load(runs: runs)
                if let region = planner.network?.region {
                    position = .region(region)
                }
            }
        }
    }

    private var plannerContent: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                plannerMap
                totalsPill
                    .padding(.top, 8)
            }
            candidateList
        }
    }

    private var candidates: [RoutePlanModel.Candidate] { planner.candidates }

    private var plannerMap: some View {
        Map(position: $position) {
            if let network = planner.network {
                // The rest of the network, dimmed context.
                ForEach(network.segments) { segment in
                    if !planner.chosenSegmentIDs.contains(segment.id),
                       !candidates.contains(where: { $0.segment.id == segment.id }) {
                        MapPolyline(coordinates: segment.coordinates)
                            .stroke(.gray.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                }
                // The route so far.
                ForEach(Array(planner.routeCoordinates.enumerated()), id: \.offset) { _, coordinates in
                    MapPolyline(coordinates: coordinates)
                        .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                // The choices, coloured to match the list below.
                ForEach(candidates) { candidate in
                    MapPolyline(coordinates: candidate.coordinates)
                        .stroke(
                            Self.palette[candidate.id % Self.palette.count].opacity(0.95),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }
                if let start = network.start {
                    Annotation("", coordinate: start) {
                        ZStack {
                            Circle()
                                .fill(.green)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            Image(systemName: "house.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 18, height: 18)
                    }
                }
                // The frontier: where the next pick sets off from.
                if let node = planner.currentNode {
                    Annotation("", coordinate: node.centerCoordinate) {
                        Circle()
                            .fill(.white)
                            .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1.5))
                            .frame(width: 13, height: 13)
                    }
                }
            }
        }
    }

    private var totalsPill: some View {
        HStack(spacing: 10) {
            Label(Format.compactDistance(planner.totalMeters), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            Label("~\(Format.duration(planner.totalSeconds))", systemImage: "clock")
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
    }

    private var candidateList: some View {
        List {
            if candidates.isEmpty {
                Text("No known segments from here — undo, or send what you have.")
                    .foregroundStyle(.secondary)
            }
            ForEach(candidates) { candidate in
                Button {
                    planner.choose(candidate)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Self.palette[candidate.id % Self.palette.count])
                            .frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Format.compactDistance(candidate.segment.lengthMeters)) · ~\(Format.duration(candidate.expectedSeconds))")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            if let back = candidate.backToStartMeters {
                                Text("then \(Format.compactDistance(back)) back to start at shortest")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
            }

            Section {
                Button {
                    sendToWatch()
                } label: {
                    Label("Send route to watch", systemImage: "applewatch")
                        .font(.body.weight(.semibold))
                }
                .disabled(planner.legs.isEmpty)

                if let sentPlanSummary {
                    HStack {
                        Text("On watch: \(sentPlanSummary)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear", role: .destructive) {
                            model.sync.clearPlannedRoute()
                            UserDefaults.standard.removeObject(forKey: Self.sentPlanKey)
                            self.sentPlanSummary = nil
                        }
                        .font(.footnote)
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 300)
    }

    private func sendToWatch() {
        guard let plan = planner.plannedRoute() else { return }
        model.sync.send(plannedRoute: plan)
        let summary = "\(Format.compactDistance(plan.totalMeters)) · ~\(Format.duration(plan.totalSeconds))"
        UserDefaults.standard.set(summary, forKey: Self.sentPlanKey)
        sentPlanSummary = summary
    }
}
