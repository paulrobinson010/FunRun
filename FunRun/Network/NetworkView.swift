import CoreLocation
import MapKit
import SwiftUI

/// The run network on a map: segments between forks as coloured routes,
/// forks as markers — one network per place you run, switchable when
/// your running spans the world.
struct NetworkView: View {
    let model: AppModel

    @State private var networks: [RouteNetwork] = []
    @State private var selectedID: Int?
    @State private var names: [Int: String] = [:]
    @State private var loading = true
    @State private var position: MapCameraPosition = .automatic
    /// Fork-to-fork timings for the tapped-segment card.
    @State private var timings: SegmentIndex?
    @State private var selectedSegmentID: Int?
    /// Visible latitude span, for a tap tolerance that scales with zoom.
    @State private var visibleLatitudeDelta: Double = 0.02

    /// Neon route palette — cyan and magenta anchor it, the rest are
    /// picked to stay legible on a dark map.
    private static let palette: [Color] = [
        Gaitway.cyan, Gaitway.magenta, .orange, .mint, .purple, .yellow, .blue, .pink, .green, .indigo,
    ]

    private var selected: RouteNetwork? {
        networks.first { $0.id == selectedID } ?? networks.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Reading your runs…")
                } else if networks.isEmpty {
                    ContentUnavailableView(
                        "No routes yet",
                        systemImage: "map",
                        description: Text("Run with the watch and your route network appears here — forks, segments and all.")
                    )
                } else if let network = selected {
                    networkMap(network)
                }
            }
            .navigationTitle("Network")
            .toolbar {
                if networks.count > 1 {
                    Menu {
                        ForEach(networks) { network in
                            Button {
                                selectedID = network.id
                                selectedSegmentID = nil
                                position = .region(network.region)
                            } label: {
                                Label(
                                    "\(name(of: network)) · \(network.runCount) runs",
                                    systemImage: network.id == selected?.id ? "checkmark" : "map"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                }
            }
            // Re-derives the networks whenever a run lands from the
            // watch, so the map is fresh without relaunching the app.
            .task(id: model.routeBackup.entries.count) {
                await load()
            }
        }
    }

    private func networkMap(_ network: RouteNetwork) -> some View {
        MapReader { proxy in
            map(network)
                .onMapCameraChange(frequency: .continuous) { context in
                    visibleLatitudeDelta = context.region.span.latitudeDelta
                }
                .onTapGesture { screenPoint in
                    if let coordinate = proxy.convert(screenPoint, from: .local) {
                        handleTap(at: coordinate, in: network)
                    }
                }
        }
    }

    private func map(_ network: RouteNetwork) -> some View {
        Map(position: $position) {
            ForEach(network.segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(
                        Self.palette[segment.id % Self.palette.count].opacity(0.22),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                    )
            }
            ForEach(network.segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(
                        Self.palette[segment.id % Self.palette.count],
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                    )
            }
            // The tapped segment, lifted with a white halo.
            if let selected = selectedSegment(in: network) {
                MapPolyline(coordinates: selected.coordinates)
                    .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: selected.coordinates)
                    .stroke(
                        Self.palette[selected.id % Self.palette.count],
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }
            ForEach(Array(network.forks.enumerated()), id: \.offset) { _, fork in
                Annotation("", coordinate: fork) {
                    Circle()
                        .fill(.orange)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .frame(width: 12, height: 12)
                }
            }
            if let start = network.start {
                Annotation("", coordinate: start) {
                    // The halo animates inside the annotation, so the
                    // map itself never redraws for it.
                    ZStack {
                        GaitwayHalo(color: .green)
                            .frame(width: 26, height: 26)
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
                    .frame(width: 26, height: 26)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let selected = selectedSegment(in: network) {
                    segmentCard(selected)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(spacing: 12) {
                    Label(count(network.forks.count, "fork"), systemImage: "arrow.triangle.branch")
                    Label(count(network.segments.count, "segment"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    Label(count(network.runCount, "run"), systemImage: "figure.run")
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.thinMaterial)
            }
        }
    }

    // MARK: - Tapped-segment card

    private func selectedSegment(in network: RouteNetwork) -> RouteNetwork.SegmentPath? {
        network.segments.first { $0.id == selectedSegmentID }
    }

    /// Tap toggles: same segment dismisses, a different one switches,
    /// empty map clears.
    private func handleTap(at coordinate: CLLocationCoordinate2D, in network: RouteNetwork) {
        let tolerance = max(35, visibleLatitudeDelta * 111_320 * 0.03)
        let tapped = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var nearest: (id: Int, meters: Double)?
        for segment in network.segments {
            for point in segment.coordinates {
                let meters = tapped.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
                if meters < (nearest?.meters ?? tolerance) {
                    nearest = (segment.id, meters)
                }
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSegmentID = nearest?.id == selectedSegmentID ? nil : nearest?.id
        }
    }

    /// Per-direction history for the tapped stretch: how often it's
    /// been run each way and the best time, the arrow pointing the way
    /// that direction travels on the map.
    private func segmentCard(_ segment: RouteNetwork.SegmentPath) -> some View {
        let directions = directionStats(for: segment)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(Self.palette[segment.id % Self.palette.count])
                    .frame(width: 10, height: 10)
                Text(Format.compactDistance(segment.lengthMeters))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedSegmentID = nil }
                    }
            }
            if directions.isEmpty {
                Text("No timed passes — timing runs fork to fork.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(directions.enumerated()), id: \.offset) { _, direction in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                        .font(.footnote.weight(.bold))
                        .rotationEffect(.degrees(direction.bearing))
                        .frame(width: 20, height: 20)
                        .background(.tint.opacity(0.15), in: Circle())
                    Text("\(direction.stats.count)× · best \(Format.duration(direction.stats.bestSeconds))")
                        .font(.subheadline)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func directionStats(for segment: RouteNetwork.SegmentPath) -> [(bearing: Double, stats: SegmentIndex.Stats)] {
        guard let timings,
              let first = segment.coordinates.first,
              let last = segment.coordinates.last else { return [] }
        // Match on the stretch's own shape, not just its endpoints:
        // the way it sets off and roughly how far it runs. Otherwise a
        // different route between the same two junctions is counted
        // here too.
        let forwardCoordinates = segment.coordinates
        let reverseCoordinates = Array(segment.coordinates.reversed())
        var rows: [(bearing: Double, stats: SegmentIndex.Stats)] = []
        if let forward = timings.stats(
            nearFrom: segment.endA,
            to: segment.endB,
            leavingOn: initialBearing(along: forwardCoordinates),
            aboutMeters: segment.lengthMeters
        ) {
            rows.append((straightBearing(from: first, to: last), forward))
        }
        if let reverse = timings.stats(
            nearFrom: segment.endB,
            to: segment.endA,
            leavingOn: initialBearing(along: reverseCoordinates),
            aboutMeters: segment.lengthMeters
        ) {
            rows.append((straightBearing(from: last, to: first), reverse))
        }
        return rows
    }

    /// How the stretch leaves its first junction — matched against the
    /// short exit bearing history records, so a few points in.
    private func initialBearing(along coordinates: [CLLocationCoordinate2D]) -> Double? {
        guard let first = coordinates.first, coordinates.count >= 2 else { return nil }
        return straightBearing(from: first, to: coordinates[min(3, coordinates.count - 1)])
    }

    private func straightBearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let pointA = TrackPoint(latitude: a.latitude, longitude: a.longitude, elapsed: 0, distanceMeters: 0, energyKilocalories: 0)
        let pointB = TrackPoint(latitude: b.latitude, longitude: b.longitude, elapsed: 0, distanceMeters: 0, energyKilocalories: 0)
        return RouteGraph.bearing(from: pointA, to: pointB)
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    private func name(of network: RouteNetwork) -> String {
        names[network.id] ?? "Network \(network.id + 1)"
    }

    private func load() async {
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
        let (built, index) = await Task.detached(priority: .userInitiated) { () -> ([RouteNetwork], SegmentIndex) in
            let networks = RouteNetworkBuilder.build(from: runs)
            let graph = RouteGraph.build(from: runs)
            return (networks, SegmentIndex.build(from: runs, graph: graph))
        }.value
        networks = built
        timings = index
        selectedSegmentID = nil
        // Only reset the selection and camera when there wasn't a valid
        // one — a refresh mid-browse keeps the user where they were.
        if !built.contains(where: { $0.id == selectedID }) {
            selectedID = built.first?.id
            if let first = built.first {
                position = .region(first.region)
            }
        }
        loading = false

        // Best-effort friendly names ("Kingston upon Thames", not
        // "Network 1"); the fallback stays if geocoding declines.
        let geocoder = CLGeocoder()
        for network in built {
            let location = CLLocation(latitude: network.center.latitude, longitude: network.center.longitude)
            if let placemark = try? await geocoder.reverseGeocodeLocation(location).first,
               let name = placemark.locality ?? placemark.subLocality ?? placemark.name {
                names[network.id] = name
            }
        }
    }
}
