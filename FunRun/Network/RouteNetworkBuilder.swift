import CoreLocation
import Foundation
import MapKit

/// One geographic run network: everywhere your routes connect — home,
/// the holiday place, the work trip — each with its own forks and
/// segments.
struct RouteNetwork: Identifiable {
    struct SegmentPath: Identifiable {
        let id: Int
        var coordinates: [CLLocationCoordinate2D]
    }

    let id: Int
    var center: CLLocationCoordinate2D
    var runCount: Int
    var forks: [CLLocationCoordinate2D]
    /// Representative geometry per fork-to-fork stretch. When no forks
    /// exist yet, these are the raw run tracks instead.
    var segments: [SegmentPath]
    var region: MKCoordinateRegion
}

/// Derives the networks from raw runs, exactly as the watch's predictor
/// sees them: grid-snapped tracks, divergence points as forks, and the
/// stretches between forks as segments — but keeping the real GPS
/// geometry so it can be drawn.
enum RouteNetworkBuilder {
    /// Runs starting within this distance of a network belong to it.
    static let clusterRadiusMeters: Double = 5_000
    /// Cap drawn segments per network so a dense year stays smooth.
    static let maximumSegments = 400

    static func build(from runs: [RouteRun]) -> [RouteNetwork] {
        // Cluster runs by where they start.
        var clusters: [[RouteRun]] = []
        var centers: [CLLocation] = []
        for run in runs {
            guard let first = run.points.first else { continue }
            let start = CLLocation(latitude: first.latitude, longitude: first.longitude)
            if let index = centers.firstIndex(where: { $0.distance(from: start) < clusterRadiusMeters }) {
                clusters[index].append(run)
            } else {
                clusters.append([run])
                centers.append(start)
            }
        }

        return clusters.enumerated().map { clusterIndex, clusterRuns in
            network(id: clusterIndex, from: clusterRuns)
        }
        .sorted { $0.runCount > $1.runCount }
    }

    private static func network(id: Int, from runs: [RouteRun]) -> RouteNetwork {
        let graph = RouteGraph.build(from: runs)
        let decisionCells = graph.decisionCells

        var forkPoints: [RouteGraph.GridKey: CLLocationCoordinate2D] = [:]
        struct SegmentKey: Hashable {
            let from: RouteGraph.GridKey
            let to: RouteGraph.GridKey
        }
        var segmentGeometry: [SegmentKey: [CLLocationCoordinate2D]] = [:]

        if !decisionCells.isEmpty {
            for run in runs {
                var lastDecision: (key: RouteGraph.GridKey, index: Int)?
                for (index, point) in run.points.enumerated() {
                    let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                    let cell = RouteGraph.GridKey(coordinate)
                    guard decisionCells.contains(cell) else { continue }
                    if forkPoints[cell] == nil {
                        forkPoints[cell] = coordinate
                    }
                    if let previous = lastDecision, previous.key != cell, index - previous.index >= 2 {
                        let key = SegmentKey(from: previous.key, to: cell)
                        let mirrored = SegmentKey(from: cell, to: previous.key)
                        if segmentGeometry[key] == nil && segmentGeometry[mirrored] == nil {
                            segmentGeometry[key] = run.points[previous.index...index].map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            }
                        }
                    }
                    lastDecision = (cell, index)
                }
            }
        }

        var paths: [RouteNetwork.SegmentPath] = segmentGeometry.values.prefix(maximumSegments)
            .enumerated()
            .map { RouteNetwork.SegmentPath(id: $0.offset, coordinates: $0.element) }

        // Before any forks exist, show the raw tracks so the map is
        // never an empty promise.
        if paths.isEmpty {
            paths = runs.prefix(20).enumerated().map { index, run in
                RouteNetwork.SegmentPath(id: index, coordinates: run.points.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
            }
        }

        let allPoints = runs.flatMap(\.points)
        let latitudes = allPoints.map(\.latitude)
        let longitudes = allPoints.map(\.longitude)
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.01, (maxLat - minLat) * 1.35),
                longitudeDelta: max(0.01, (maxLon - minLon) * 1.35)
            )
        )

        return RouteNetwork(
            id: id,
            center: center,
            runCount: runs.count,
            forks: Array(forkPoints.values),
            segments: paths,
            region: region
        )
    }
}
