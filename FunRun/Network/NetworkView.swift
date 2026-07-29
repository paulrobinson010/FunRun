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

    private static let palette: [Color] = [
        .cyan, .pink, .orange, .green, .purple, .yellow, .blue, .mint, .red, .indigo,
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
            .task {
                await load()
            }
        }
    }

    private func networkMap(_ network: RouteNetwork) -> some View {
        Map(position: $position) {
            ForEach(network.segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(
                        Self.palette[segment.id % Self.palette.count].opacity(0.85),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                    )
            }
            ForEach(Array(network.junctions.enumerated()), id: \.offset) { _, junction in
                Annotation("", coordinate: junction) {
                    Circle()
                        .fill(.black.opacity(0.55))
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                        .frame(width: 9, height: 9)
                }
            }
            ForEach(Array(network.forks.enumerated()), id: \.offset) { _, fork in
                Annotation("", coordinate: fork) {
                    Circle()
                        .fill(.orange)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .frame(width: 12, height: 12)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Label(count(network.forks.count, "fork"), systemImage: "arrow.triangle.branch")
                Label(count(network.junctions.count, "junction"), systemImage: "circle.circle")
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

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    private func name(of network: RouteNetwork) -> String {
        names[network.id] ?? "Network \(network.id + 1)"
    }

    private func load() async {
        guard loading else { return }
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
        let built = await Task.detached(priority: .userInitiated) {
            RouteNetworkBuilder.build(from: runs)
        }.value
        networks = built
        selectedID = built.first?.id
        if let first = built.first {
            position = .region(first.region)
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
