import CoreLocation
import Foundation
import Observation

/// Builds a planned route over the learned network, one segment at a
/// time: from the current node, every connected segment is a candidate;
/// picking one extends the route and moves the frontier to its far end.
@MainActor
@Observable
final class RoutePlanModel {
    struct Candidate: Identifiable {
        let id: Int
        var segment: RouteNetwork.SegmentPath
        /// True when the route travels the geometry endB → endA.
        var reversed: Bool
        var fromNode: RouteGraph.GridKey
        var toNode: RouteGraph.GridKey
        var expectedSeconds: TimeInterval
        var exitBearing: Double
        /// Shortest known way back to the start from this segment's far
        /// end, by distance — nil when no path back exists yet.
        var backToStartMeters: Double?

        /// Travel-ordered geometry.
        var coordinates: [CLLocationCoordinate2D] {
            reversed ? segment.coordinates.reversed() : segment.coordinates
        }
    }

    struct Leg {
        var candidate: Candidate
    }

    private(set) var network: RouteNetwork?
    private(set) var legs: [Leg] = []
    private(set) var loading = true
    /// Frontier: where the next segment must start.
    private(set) var currentNode: RouteGraph.GridKey?
    private(set) var startNode: RouteGraph.GridKey?

    private var segmentStats: SegmentIndex?
    /// Overall average speed across history, the timing fallback for
    /// stretches with no fork-to-fork record (the tails past the last
    /// fork).
    private var averageSpeed: Double = 2.4

    var totalMeters: Double { legs.reduce(0) { $0 + $1.candidate.segment.lengthMeters } }
    var totalSeconds: TimeInterval { legs.reduce(0) { $0 + $1.candidate.expectedSeconds } }

    /// Node identity is tolerant: endpoint cells within 3 cells are the
    /// same junction (matching the network builder's dedupe).
    static func near(_ a: RouteGraph.GridKey, _ b: RouteGraph.GridKey) -> Bool {
        max(abs(a.x - b.x), abs(a.y - b.y)) <= 3
    }

    func load(runs allRuns: [RouteRun]) {
        let networks = RouteNetworkBuilder.build(from: allRuns)
        network = networks.first
        let graph = RouteGraph.build(from: allRuns)
        segmentStats = SegmentIndex.build(from: allRuns, graph: graph)
        let meters = allRuns.reduce(0) { $0 + $1.totalDistanceMeters }
        let seconds = allRuns.reduce(0) { $0 + $1.totalSeconds }
        if meters > 1000, seconds > 0 {
            averageSpeed = meters / seconds
        }
        if let start = network?.start {
            startNode = RouteGraph.GridKey(start)
        }
        reset()
        loading = false
    }

    func reset() {
        legs = []
        currentNode = startNode
    }

    func undo() {
        legs.removeLast()
        currentNode = legs.last?.candidate.toNode ?? startNode
    }

    func choose(_ candidate: Candidate) {
        legs.append(Leg(candidate: candidate))
        currentNode = candidate.toNode
    }

    /// Segment ids already in the route, for dimming on the map.
    var chosenSegmentIDs: Set<Int> {
        Set(legs.map(\.candidate.segment.id))
    }

    /// The chosen route's travel-ordered geometry, for the highlight.
    var routeCoordinates: [[CLLocationCoordinate2D]] {
        legs.map(\.candidate.coordinates)
    }

    /// Every segment leaving the frontier node.
    var candidates: [Candidate] {
        guard let network, let currentNode else { return [] }
        let back = backDistances()
        var result: [Candidate] = []
        for segment in network.segments {
            let orientations: [(reversed: Bool, from: RouteGraph.GridKey, to: RouteGraph.GridKey)] = [
                (false, segment.endA, segment.endB),
                (true, segment.endB, segment.endA),
            ]
            for orientation in orientations where Self.near(orientation.from, currentNode) {
                let coordinates = orientation.reversed ? segment.coordinates.reversed() : segment.coordinates
                guard coordinates.count >= 2 else { continue }
                let bearingSample = coordinates[min(3, coordinates.count - 1)]
                result.append(Candidate(
                    id: result.count,
                    segment: segment,
                    reversed: orientation.reversed,
                    fromNode: orientation.from,
                    toNode: orientation.to,
                    expectedSeconds: expectedSeconds(
                        from: orientation.from,
                        to: orientation.to,
                        lengthMeters: segment.lengthMeters,
                        exitBearing: bearing(from: coordinates[0], to: bearingSample)
                    ),
                    exitBearing: bearing(from: coordinates[0], to: bearingSample),
                    backToStartMeters: back.first { Self.near($0.node, orientation.to) }?.meters
                ))
                break  // a same-fork loop matches both ways; offer it once per pass
            }
        }
        return result
    }

    /// Typical time over a stretch: fork-to-fork history when it exists
    /// (either direction), overall average pace when it doesn't.
    private func expectedSeconds(
        from: RouteGraph.GridKey,
        to: RouteGraph.GridKey,
        lengthMeters: Double,
        exitBearing: Double
    ) -> TimeInterval {
        // Same shape test as the network card: a different way round
        // between these two junctions is not this leg.
        if let stats = segmentStats?.stats(
            nearFrom: from, to: to, leavingOn: exitBearing, aboutMeters: lengthMeters
        ) {
            return stats.averageSeconds
        }
        return lengthMeters / averageSpeed
    }

    // MARK: - Shortest way back (distance), over the whole network

    /// Dijkstra over the segment graph from the start node; segments are
    /// undirected edges weighted by length.
    private func backDistances() -> [(node: RouteGraph.GridKey, meters: Double)] {
        guard let network, let startNode else { return [] }

        // Canonicalise endpoint cells into representative nodes.
        var representatives: [RouteGraph.GridKey] = []
        func representative(_ key: RouteGraph.GridKey) -> Int {
            if let index = representatives.firstIndex(where: { Self.near($0, key) }) {
                return index
            }
            representatives.append(key)
            return representatives.count - 1
        }

        var edges: [(a: Int, b: Int, meters: Double)] = []
        for segment in network.segments {
            edges.append((representative(segment.endA), representative(segment.endB), segment.lengthMeters))
        }
        let source = representative(startNode)

        var distance = [Int: Double](minimumCapacity: representatives.count)
        distance[source] = 0
        var settled: Set<Int> = []
        while settled.count < representatives.count {
            guard let (node, best) = distance
                .filter({ !settled.contains($0.key) })
                .min(by: { $0.value < $1.value }) else { break }
            settled.insert(node)
            for edge in edges {
                let neighbour: Int
                if edge.a == node { neighbour = edge.b }
                else if edge.b == node { neighbour = edge.a }
                else { continue }
                let candidate = best + edge.meters
                if candidate < distance[neighbour] ?? .infinity {
                    distance[neighbour] = candidate
                }
            }
        }
        return distance.map { (representatives[$0.key], $0.value) }
    }

    private func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let pointA = TrackPoint(latitude: a.latitude, longitude: a.longitude, elapsed: 0, distanceMeters: 0, energyKilocalories: 0)
        let pointB = TrackPoint(latitude: b.latitude, longitude: b.longitude, elapsed: 0, distanceMeters: 0, energyKilocalories: 0)
        return RouteGraph.bearing(from: pointA, to: pointB)
    }

    /// The finished plan, ready for the watch.
    func plannedRoute() -> PlannedRoute? {
        guard !legs.isEmpty else { return nil }
        return PlannedRoute(legs: legs.map { leg in
            PlannedRoute.Leg(
                from: leg.candidate.fromNode,
                to: leg.candidate.toNode,
                exitBearing: leg.candidate.exitBearing,
                distanceMeters: leg.candidate.segment.lengthMeters,
                expectedSeconds: leg.candidate.expectedSeconds
            )
        })
    }
}
