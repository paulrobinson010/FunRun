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
    /// Forks: real intersections — three or more directions meeting,
    /// coalesced across GPS drift. Visible from the first run.
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
        let nodeCells = graph.decisionCells
        // Forks are coalesced to a canonical cell; match passes within
        // ~2 cells so drift still snaps to the right fork.
        let nearFork: (RouteGraph.GridKey) -> RouteGraph.GridKey? = { cell in
            cell.neighbours(radius: 2).first { nodeCells.contains($0) }
        }

        // Place each fork dot at the average of the GPS points that pass
        // through its canonical cell, so it sits on the actual path.
        var forkSums: [RouteGraph.GridKey: (latitude: Double, longitude: Double, count: Double)] = [:]
        for run in runs {
            for point in run.points {
                let cell = RouteGraph.GridKey(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                guard nodeCells.contains(cell) else { continue }
                var sum = forkSums[cell] ?? (0, 0, 0)
                sum.latitude += point.latitude
                sum.longitude += point.longitude
                sum.count += 1
                forkSums[cell] = sum
            }
        }
        var forkPoints: [RouteGraph.GridKey: CLLocationCoordinate2D] = forkSums.mapValues {
            CLLocationCoordinate2D(latitude: $0.latitude / $0.count, longitude: $0.longitude / $0.count)
        }
        // Keyed by endpoints plus the initial-bearing sector, so a loop
        // that leaves a fork and returns to the same fork keeps its two
        // distinct exits, while repeat traversals of the same stretch
        // dedupe to one drawn line per direction.
        struct SegmentKey: Hashable {
            let from: RouteGraph.GridKey
            let to: RouteGraph.GridKey
            let sector: Int
        }
        var segmentGeometry: [SegmentKey: [CLLocationCoordinate2D]] = [:]

        func emit(_ run: RouteRun, from: (key: RouteGraph.GridKey, index: Int), to: (key: RouteGraph.GridKey, index: Int)) {
            // Same-fork loops need real length; different-fork stretches
            // just need a few points. Guards out dwell noise at a fork.
            let minimumGap = from.key == to.key ? 10 : 3
            guard to.index - from.index >= minimumGap else { return }
            let bearingSampleEnd = min(from.index + 3, to.index)
            let initialBearing = RouteGraph.bearing(from: run.points[from.index], to: run.points[bearingSampleEnd])
            let key = SegmentKey(from: from.key, to: to.key, sector: Int(initialBearing / 60) % 6)
            guard segmentGeometry[key] == nil else { return }
            var coordinates = run.points[from.index...to.index].map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            // Passes snap to a fork from ~2 cells out, which would leave
            // every segment stopping short of the dot; pin the ends to
            // the fork itself so the network draws joined-up.
            if let anchor = forkPoints[from.key] {
                coordinates.insert(anchor, at: 0)
            }
            if let anchor = forkPoints[to.key] {
                coordinates.append(anchor)
            }
            segmentGeometry[key] = coordinates
        }

        for run in runs {
            guard run.points.count >= 2 else { continue }
            // The run start is a node too, so the stretch before the
            // first fork is drawn; likewise the tail after the last.
            var lastNode: (key: RouteGraph.GridKey, index: Int) = (
                RouteGraph.GridKey(CLLocationCoordinate2D(
                    latitude: run.points[0].latitude, longitude: run.points[0].longitude
                )),
                0
            )
            for (index, point) in run.points.enumerated() {
                let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                guard let cell = nearFork(RouteGraph.GridKey(coordinate)) else { continue }
                if forkPoints[cell] == nil {
                    forkPoints[cell] = coordinate
                }
                emit(run, from: lastNode, to: (cell, index))
                lastNode = (cell, index)
            }
            let endIndex = run.points.count - 1
            let endCell = RouteGraph.GridKey(CLLocationCoordinate2D(
                latitude: run.points[endIndex].latitude, longitude: run.points[endIndex].longitude
            ))
            emit(run, from: lastNode, to: (endCell, endIndex))
        }

        let paths: [RouteNetwork.SegmentPath] = segmentGeometry.values.prefix(maximumSegments)
            .enumerated()
            .map { RouteNetwork.SegmentPath(id: $0.offset, coordinates: $0.element) }

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
