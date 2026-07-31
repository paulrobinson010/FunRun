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
        /// Grid cells at each end of the geometry — the nodes this
        /// stretch connects, for the route planner's graph walking.
        var endA: RouteGraph.GridKey
        var endB: RouteGraph.GridKey
        var lengthMeters: Double
    }

    let id: Int
    var center: CLLocationCoordinate2D
    var runCount: Int
    /// Forks: real intersections — three or more directions meeting,
    /// coalesced across GPS drift. Visible from the first run.
    var forks: [CLLocationCoordinate2D]
    /// Where runs in this network usually start — home, in practice.
    var start: CLLocationCoordinate2D?
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
        // A segment is one *physical* stretch, whichever direction it
        // was run and whichever run recorded it. Two traversals count as
        // the same stretch when both ends and the midpoint all land
        // within ~3 cells of each other — direction-agnostic, tolerant
        // of drift, but two genuinely different routes between the same
        // forks keep distinct midpoints and both get drawn.
        struct SegmentSignature {
            var endA: RouteGraph.GridKey
            var endB: RouteGraph.GridKey
            var mid: RouteGraph.GridKey
        }
        var accepted: [(signature: SegmentSignature, coordinates: [CLLocationCoordinate2D])] = []

        func near(_ a: RouteGraph.GridKey, _ b: RouteGraph.GridKey) -> Bool {
            max(abs(a.x - b.x), abs(a.y - b.y)) <= 3
        }

        func isDuplicate(_ signature: SegmentSignature) -> Bool {
            accepted.contains { existing in
                let e = existing.signature
                let sameEnds = (near(e.endA, signature.endA) && near(e.endB, signature.endB))
                    || (near(e.endA, signature.endB) && near(e.endB, signature.endA))
                return sameEnds && near(e.mid, signature.mid)
            }
        }

        func emit(_ run: RouteRun, from: (key: RouteGraph.GridKey, index: Int), to: (key: RouteGraph.GridKey, index: Int)) {
            // Same-fork loops need real length; different-fork stretches
            // just need a few points. Guards out dwell noise at a fork.
            let minimumGap = from.key == to.key ? 10 : 3
            guard to.index - from.index >= minimumGap else { return }
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
            let signature = SegmentSignature(
                endA: RouteGraph.GridKey(coordinates[0]),
                endB: RouteGraph.GridKey(coordinates[coordinates.count - 1]),
                mid: RouteGraph.GridKey(coordinates[coordinates.count / 2])
            )
            guard !isDuplicate(signature) else { return }
            accepted.append((signature, coordinates))
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

        let paths: [RouteNetwork.SegmentPath] = accepted.prefix(maximumSegments)
            .enumerated()
            .map { index, item in
                var length = 0.0
                for pair in zip(item.coordinates, item.coordinates.dropFirst()) {
                    length += CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                        .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
                }
                return RouteNetwork.SegmentPath(
                    id: index,
                    coordinates: item.coordinates,
                    endA: item.signature.endA,
                    endB: item.signature.endB,
                    lengthMeters: length
                )
            }

        // Where this network's runs set off from: the busiest starting
        // cell, averaged — the planner's default start, and a marker on
        // the map.
        let startGroups = Dictionary(grouping: runs.compactMap(\.points.first)) {
            RouteGraph.GridKey(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
        }
        let start = startGroups.values.max { $0.count < $1.count }.map { starts in
            CLLocationCoordinate2D(
                latitude: starts.map(\.latitude).reduce(0, +) / Double(starts.count),
                longitude: starts.map(\.longitude).reduce(0, +) / Double(starts.count)
            )
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
            start: start,
            segments: paths,
            region: region
        )
    }
}
