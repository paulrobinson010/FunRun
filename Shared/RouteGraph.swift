import CoreLocation
import Foundation

/// The map your past runs draw. Tracks are snapped to a coarse grid;
/// where two passes stop sharing a corridor (or separate corridors
/// merge), that's a decision point. Every traversal remembers how much time and energy
/// was still to come in that run, so each branch's outcomes are the
/// *actual* endings of runs that took it — later intersections are
/// automatically averaged in, weighted by how often each onward choice
/// was made. That's the probability handling: expected values over your
/// real history, not a single guessed route.
struct RouteGraph {
    /// Grid cell size. Coarse enough that GPS noise puts repeat visits in
    /// the same cell, fine enough to keep nearby streets apart.
    static let cellMeters: Double = 18

    /// Outgoing directions less than this far apart count as one branch.
    static let clusterWidthDegrees: Double = 45

    /// A branch needs this many past traversals to be trusted.
    static let minimumSamplesPerBranch = 2

    struct GridKey: Hashable {
        var x: Int
        var y: Int

        init(_ coordinate: CLLocationCoordinate2D) {
            let metersPerDegreeLatitude = 111_320.0
            let metersPerDegreeLongitude = 111_320.0 * cos(coordinate.latitude * .pi / 180)
            y = Int((coordinate.latitude * metersPerDegreeLatitude / RouteGraph.cellMeters).rounded(.down))
            x = Int((coordinate.longitude * metersPerDegreeLongitude / RouteGraph.cellMeters).rounded(.down))
        }

        init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }

        /// This cell plus the 8 around it, for tolerant live matching.
        var selfAndNeighbours: [GridKey] {
            neighbours(radius: 1)
        }

        /// The square of cells within `radius` of this one (inclusive).
        func neighbours(radius: Int) -> [GridKey] {
            (-radius...radius).flatMap { dy in
                (-radius...radius).map { dx in GridKey(x: x + dx, y: y + dy) }
            }
        }
    }

    struct Traversal {
        var approachBearing: Double
        var outgoingBearing: Double
        var remainingSeconds: TimeInterval
        var remainingEnergy: Double
    }

    /// One choice at a decision point, with its expected outcome.
    struct Branch {
        var bearing: Double
        var expectedRemainingSeconds: TimeInterval
        var expectedRemainingEnergy: Double
        var sampleCount: Int
        /// Share of matching past traversals that went this way.
        var probability: Double
    }

    private var nodes: [GridKey: [Traversal]] = [:]

    /// Forks: places where the run network genuinely branches — where
    /// passes that had been sharing a corridor part ways, or separate
    /// corridors merge. Found by comparing whole paths rather than
    /// bearing statistics, so a zigzagged, curved or drifting corridor
    /// never fakes one: a fork needs the other pass to actually go
    /// somewhere else.
    private(set) var decisionCells: Set<GridKey> = []

    static func build(from runs: [RouteRun]) -> RouteGraph {
        var graph = RouteGraph()
        let paths = runs.map { cellPath(for: $0) }
        for (runIndex, run) in runs.enumerated() {
            let path = paths[runIndex]
            for index in path.indices {
                let step = path[index]
                guard let outgoing = step.outgoingBearing else { continue }
                let approach = index > 0
                    ? bearing(from: path[index - 1].point, to: step.point)
                    : outgoing
                let remainingSeconds = run.totalSeconds - step.point.elapsed
                let remainingEnergy = run.totalEnergyKilocalories - step.point.energyKilocalories
                guard remainingSeconds > 0 else { continue }
                graph.nodes[step.key, default: []].append(Traversal(
                    approachBearing: approach,
                    outgoingBearing: outgoing,
                    remainingSeconds: remainingSeconds,
                    remainingEnergy: max(0, remainingEnergy)
                ))
            }
        }
        // A fork is where the network actually branches: the last shared
        // cell before two passes that had been running the same corridor
        // go separate ways, or the first shared cell where separate
        // corridors merge. Every pair of paths is compared — each path
        // against itself too, which is what finds the mouth of a loop.
        // No bearing statistics anywhere: a corridor can wiggle, zigzag
        // or drift between days and never produce a fork, because a fork
        // needs the other pass to genuinely go somewhere else.
        let indexMaps: [[GridKey: [Int]]] = paths.map { path in
            var map: [GridKey: [Int]] = [:]
            for (index, step) in path.enumerated() {
                map[step.key, default: []].append(index)
            }
            return map
        }
        // Runs from different areas (home vs. holiday) can never share a
        // corridor; skip those pairs outright.
        let boxes: [(minX: Int, maxX: Int, minY: Int, maxY: Int)] = paths.map { path in
            let xs = path.map(\.key.x)
            let ys = path.map(\.key.y)
            return (xs.min() ?? 0, xs.max() ?? 0, ys.min() ?? 0, ys.max() ?? 0)
        }
        var votes: [GridKey: Int] = [:]
        for a in paths.indices {
            for b in paths.indices {
                guard boxes[a].minX <= boxes[b].maxX + 3, boxes[b].minX <= boxes[a].maxX + 3,
                      boxes[a].minY <= boxes[b].maxY + 3, boxes[b].minY <= boxes[a].maxY + 3 else { continue }
                for key in divergenceEvents(
                    along: paths[a],
                    against: paths[b],
                    otherIndices: indexMaps[b],
                    isSelf: a == b
                ) {
                    votes[key, default: 0] += 1
                }
            }
        }
        // Drift and matching tolerance spread one junction's events over
        // a few cells (a loop mouth's exit and return land ~3 apart);
        // coalesce within 3. Every real fork is seen from both sides of
        // a pair — or as both the exit and the return of a loop — so a
        // cluster needs at least two votes; a lone event is noise.
        var remaining = votes
        while let seed = remaining.max(by: { $0.value < $1.value }) {
            var total = 0
            for neighbour in seed.key.neighbours(radius: 3) {
                if let count = remaining.removeValue(forKey: neighbour) {
                    total += count
                }
            }
            if total >= 2 {
                graph.decisionCells.insert(seed.key)
            }
        }
        return graph
    }

    /// Walks `path` against `other`, returning the boundary cell of each
    /// sustained divergence (the last cell the two shared) and each
    /// sustained convergence (the first cell they share). Together means
    /// within ~1 cell; a break only counts once the paths are beyond ~3
    /// cells for several consecutive cells, so momentary GPS drift never
    /// splits a corridor. Self-comparison only pairs cells revisited far
    /// apart along the path — an out-and-back tip or a zigzag never
    /// pairs with itself, but the mouth of a genuine loop does — and
    /// cross-comparison ignores boundaries at either path's ends, where
    /// a run simply starting or stopping is not a junction.
    private static func divergenceEvents(
        along path: [CellStep],
        against other: [CellStep],
        otherIndices: [GridKey: [Int]],
        isSelf: Bool
    ) -> [GridKey] {
        // Tuning, in cells (~18 m each).
        let togetherRadius = 1
        let apartRadius = 3
        let persistence = 4
        let endpointGuard = 8
        let minimumSelfGap = 40
        let selfBoundaryBand = 50

        guard path.count > 2 * endpointGuard, other.count > 2 * endpointGuard else { return [] }

        func match(at index: Int, radius: Int) -> Int? {
            for cell in path[index].key.neighbours(radius: radius) {
                for j in otherIndices[cell] ?? [] where !isSelf || abs(j - index) > minimumSelfGap {
                    return j
                }
            }
            return nil
        }

        func isRealBoundary(_ boundary: (i: Int, j: Int)) -> Bool {
            // A boundary match barely past the pairing gap is the
            // pairing gap itself vanishing (an out-and-back tip), not a
            // loop mouth.
            if isSelf, abs(boundary.j - boundary.i) <= selfBoundaryBand {
                return false
            }
            // A boundary at either path's ends is a run starting or
            // stopping — or a loop closing at the front door — not a
            // junction.
            guard boundary.j >= endpointGuard, boundary.j < other.count - endpointGuard else { return false }
            return boundary.i >= endpointGuard && boundary.i < path.count - endpointGuard
        }

        var events: [GridKey] = []
        var together = match(at: 0, radius: togetherRadius) != nil
        var lastShared: (i: Int, j: Int)?
        var firstShared: (i: Int, j: Int)?
        var streak = 0

        for i in path.indices {
            let near = match(at: i, radius: togetherRadius)
            if together {
                if let near {
                    lastShared = (i, near)
                    streak = 0
                } else if match(at: i, radius: apartRadius) != nil {
                    streak = 0
                } else {
                    streak += 1
                    if streak >= persistence {
                        together = false
                        streak = 0
                        if let boundary = lastShared, isRealBoundary(boundary) {
                            events.append(path[boundary.i].key)
                        }
                    }
                }
            } else {
                if let near {
                    if firstShared == nil {
                        firstShared = (i, near)
                    }
                    streak += 1
                    if streak >= persistence {
                        together = true
                        streak = 0
                        if let boundary = firstShared, isRealBoundary(boundary) {
                            events.append(path[boundary.i].key)
                        }
                        lastShared = firstShared
                        firstShared = nil
                    }
                } else {
                    firstShared = nil
                    streak = 0
                }
            }
        }
        return events
    }

    /// The branches at this fork for someone moving on this course —
    /// every direction history has left it in, except the one behind
    /// you. Outcomes pool across all approaches: how long "east from
    /// here" takes doesn't depend on how you arrived. Traversals gather
    /// from the neighbouring cells too, since drift spreads a corner's
    /// traffic over ~a cell either side.
    func branches(at key: GridKey, course: Double) -> [Branch] {
        guard decisionCells.contains(key) else { return [] }
        var traversals: [Traversal] = []
        for cell in key.neighbours(radius: 2) {
            traversals.append(contentsOf: nodes[cell] ?? [])
        }
        guard traversals.count >= Self.minimumSamplesPerBranch * 2 else { return [] }

        let backTheWayYouCame = (course + 180).truncatingRemainder(dividingBy: 360)
        let clusters = Self.clusterBearings(traversals.map(\.outgoingBearing))
        let branches: [Branch] = clusters.compactMap { memberIndices in
            guard memberIndices.count >= Self.minimumSamplesPerBranch else { return nil }
            let members = memberIndices.map { traversals[$0] }
            let bearing = Self.circularMean(members.map(\.outgoingBearing))
            guard Self.angularDistance(bearing, backTheWayYouCame) > 45 else { return nil }
            return Branch(
                bearing: bearing,
                expectedRemainingSeconds: members.map(\.remainingSeconds).reduce(0, +) / Double(members.count),
                expectedRemainingEnergy: members.map(\.remainingEnergy).reduce(0, +) / Double(members.count),
                sampleCount: members.count,
                probability: 0
            )
        }
        guard branches.count >= 2 else { return [] }
        // Probability = choice share among the options actually offered.
        let total = Double(branches.reduce(0) { $0 + $1.sampleCount })
        return branches
            .map { branch in
                var branch = branch
                branch.probability = Double(branch.sampleCount) / total
                return branch
            }
            .sorted { $0.probability > $1.probability }
    }

    // MARK: - Track → cell path

    struct CellStep {
        var key: GridKey
        var point: TrackPoint
        var outgoingBearing: Double?
    }

    static func cellPath(for run: RouteRun) -> [CellStep] {
        var steps: [CellStep] = []
        for point in run.points {
            let key = GridKey(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            if steps.last?.key != key {
                steps.append(CellStep(key: key, point: point, outgoingBearing: nil))
            }
        }
        for index in steps.indices.dropLast() {
            steps[index].outgoingBearing = bearing(from: steps[index].point, to: steps[index + 1].point)
        }
        return steps
    }

    // MARK: - Bearing maths

    static func bearing(from a: TrackPoint, to b: TrackPoint) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    static func circularMean(_ bearings: [Double]) -> Double {
        let x = bearings.map { cos($0 * .pi / 180) }.reduce(0, +)
        let y = bearings.map { sin($0 * .pi / 180) }.reduce(0, +)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Groups bearings into clusters no wider apart than `width`,
    /// respecting the 0°/360° wrap. Returns index groups into the input
    /// array.
    static func clusterBearings(_ bearings: [Double], width: Double = RouteGraph.clusterWidthDegrees) -> [[Int]] {
        guard !bearings.isEmpty else { return [] }
        let sorted = bearings.indices.sorted { bearings[$0] < bearings[$1] }
        // Find the largest gap around the circle and cut there, so a
        // cluster straddling north isn't split artificially.
        var largestGap = -1.0
        var cutPosition = 0
        for position in sorted.indices {
            let current = bearings[sorted[position]]
            let next = bearings[sorted[(position + 1) % sorted.count]]
            let gap = (next - current + 360).truncatingRemainder(dividingBy: 360)
            if gap > largestGap {
                largestGap = gap
                cutPosition = (position + 1) % sorted.count
            }
        }
        let rotated = Array(sorted[cutPosition...] + sorted[..<cutPosition])
        var clusters: [[Int]] = [[rotated[0]]]
        for position in 1..<rotated.count {
            let previous = bearings[rotated[position - 1]]
            let current = bearings[rotated[position]]
            let gap = (current - previous + 360).truncatingRemainder(dividingBy: 360)
            if gap <= width {
                clusters[clusters.count - 1].append(rotated[position])
            } else {
                clusters.append([rotated[position]])
            }
        }
        return clusters
    }
}
