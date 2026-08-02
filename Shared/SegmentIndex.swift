import Foundation

/// The stretches between decision points, from recent history. Each
/// traversal of a stretch remembers how long it took and which way it set
/// off, so a finished segment can be compared against your recent typical
/// and best, and each branch at a fork can quote the expected time to the
/// next fork.
struct SegmentIndex {
    struct Traversal {
        var to: RouteGraph.GridKey
        var startBearing: Double
        var seconds: TimeInterval
        var distanceMeters: Double
    }

    struct Stats {
        var averageSeconds: TimeInterval
        var bestSeconds: TimeInterval
        var count: Int
    }

    /// What a fork can quote about one of its branches: how long the
    /// stretch to the next fork is, and the fastest it's been covered.
    struct BranchStats {
        var medianMeters: Double
        /// Best pace over the stretch — the time to beat. Nil when no
        /// traversal was long enough to give an honest pace.
        var bestSecondsPerKm: Double?
        var count: Int
    }

    /// Segments shorter than this are grid noise, not a real stretch.
    static let minimumSegmentSeconds: TimeInterval = 30

    private var byFromCell: [RouteGraph.GridKey: [Traversal]] = [:]

    static func build(from runs: [RouteRun], graph: RouteGraph) -> SegmentIndex {
        var index = SegmentIndex()
        guard !graph.decisionCells.isEmpty else { return index }
        for run in runs {
            var last: (key: RouteGraph.GridKey, elapsed: TimeInterval, distance: Double, bearing: Double?)?
            for rawStep in RouteGraph.cellPath(for: run) {
                // Forks are coalesced to a canonical cell; snap passes
                // within ~2 cells of one onto it.
                guard let node = rawStep.key.neighbours(radius: 2).first(where: graph.decisionCells.contains) else { continue }
                var step = rawStep
                step.key = node
                if let previous = last, previous.key != step.key {
                    let seconds = step.point.elapsed - previous.elapsed
                    if seconds >= minimumSegmentSeconds, let bearing = previous.bearing {
                        index.byFromCell[previous.key, default: []].append(Traversal(
                            to: step.key,
                            startBearing: bearing,
                            seconds: seconds,
                            distanceMeters: max(0, step.point.distanceMeters - previous.distance)
                        ))
                    }
                }
                last = (step.key, step.point.elapsed, step.point.distanceMeters, step.outgoingBearing)
            }
        }
        return index
    }

    /// History for the exact segment just completed. The destination is
    /// matched with one cell of tolerance, since GPS can put the same
    /// corner in a neighbouring cell on different days.
    func stats(from: RouteGraph.GridKey, to: RouteGraph.GridKey) -> Stats? {
        let targets = Set(to.selfAndNeighbours)
        let matches = (byFromCell[from] ?? []).filter { targets.contains($0.to) }
        guard !matches.isEmpty else { return nil }
        let seconds = matches.map(\.seconds)
        return Stats(
            averageSeconds: seconds.reduce(0, +) / Double(seconds.count),
            bestSeconds: seconds.min() ?? 0,
            count: matches.count
        )
    }

    /// Every stretch as a routing edge, for pathfinding over the known
    /// network (take-me-home).
    var edges: [(from: RouteGraph.GridKey, to: RouteGraph.GridKey, startBearing: Double, seconds: TimeInterval)] {
        byFromCell.flatMap { from, traversals in
            traversals.map { (from, $0.to, $0.startBearing, $0.seconds) }
        }
    }

    /// All recorded traversals leaving this fork.
    func traversals(from: RouteGraph.GridKey) -> [Traversal] {
        byFromCell[from] ?? []
    }

    /// Stats with endpoint tolerance on the `from` side too — for
    /// callers holding geometry-end cells rather than canonical fork
    /// cells (the network map, the route planner).
    func stats(nearFrom from: RouteGraph.GridKey, to: RouteGraph.GridKey) -> Stats? {
        for candidate in from.neighbours(radius: 2) {
            if let stats = stats(from: candidate, to: to) {
                return stats
            }
        }
        return nil
    }

    /// The stretch behind one branch of a fork: length and the fastest
    /// pace it's been covered at, from traversals setting off in this
    /// direction.
    func branchStats(from: RouteGraph.GridKey, startBearing: Double, toleranceDegrees: Double = 40) -> BranchStats? {
        let traversals = byFromCell[from] ?? []
        guard !traversals.isEmpty else { return nil }

        // Group by where each pass ended up: one group is one real
        // fork-to-fork segment. Taking a median across every direction
        // at once was how a short neighbouring branch could stand in
        // for the long one actually being run — the mixture belonged to
        // no segment at all.
        var groups: [(to: RouteGraph.GridKey, items: [Traversal])] = []
        for traversal in traversals {
            let match = groups.firstIndex {
                max(abs($0.to.x - traversal.to.x), abs($0.to.y - traversal.to.y)) <= 2
            }
            if let match {
                groups[match].items.append(traversal)
            } else {
                groups.append((traversal.to, [traversal]))
            }
        }

        // The group whose exit direction best matches the way you left.
        let candidates = groups.compactMap { group -> (offset: Double, items: [Traversal])? in
            let exit = RouteGraph.circularMean(group.items.map(\.startBearing))
            let offset = RouteGraph.angularDistance(exit, startBearing)
            return offset <= toleranceDegrees ? (offset, group.items) : nil
        }
        guard let best = candidates.min(by: { $0.offset < $1.offset }) else { return nil }

        let meters = best.items.map(\.distanceMeters).sorted()
        let paces = best.items.compactMap { traversal -> Double? in
            guard traversal.distanceMeters > 150 else { return nil }
            return traversal.seconds / (traversal.distanceMeters / 1000)
        }
        return BranchStats(
            medianMeters: meters[meters.count / 2],
            bestSecondsPerKm: paces.min(),
            count: best.items.count
        )
    }
}
