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
    }

    struct Stats {
        var averageSeconds: TimeInterval
        var bestSeconds: TimeInterval
        var count: Int
    }

    /// Segments shorter than this are grid noise, not a real stretch.
    static let minimumSegmentSeconds: TimeInterval = 30

    private var byFromCell: [RouteGraph.GridKey: [Traversal]] = [:]

    static func build(from runs: [RouteRun], graph: RouteGraph) -> SegmentIndex {
        var index = SegmentIndex()
        guard !graph.decisionCells.isEmpty else { return index }
        for run in runs {
            var last: (key: RouteGraph.GridKey, elapsed: TimeInterval, bearing: Double?)?
            for step in RouteGraph.cellPath(for: run) where graph.decisionCells.contains(step.key) {
                if let previous = last, previous.key != step.key {
                    let seconds = step.point.elapsed - previous.elapsed
                    if seconds >= minimumSegmentSeconds, let bearing = previous.bearing {
                        index.byFromCell[previous.key, default: []].append(Traversal(
                            to: step.key,
                            startBearing: bearing,
                            seconds: seconds
                        ))
                    }
                }
                last = (step.key, step.point.elapsed, step.outgoingBearing)
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

    /// Expected time from this fork to the next one, setting off in this
    /// direction.
    func expectedSeconds(from: RouteGraph.GridKey, startBearing: Double) -> TimeInterval? {
        let matches = (byFromCell[from] ?? []).filter {
            RouteGraph.angularDistance($0.startBearing, startBearing) <= RouteGraph.clusterWidthDegrees
        }
        guard matches.count >= RouteGraph.minimumSamplesPerBranch else { return nil }
        return matches.map(\.seconds).reduce(0, +) / Double(matches.count)
    }
}
