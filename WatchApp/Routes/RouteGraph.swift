import CoreLocation
import Foundation

/// The map your past runs draw. Tracks are snapped to a coarse grid; a
/// cell where past traversals leave in two or more distinct directions is
/// a decision point. Every traversal remembers how much time and energy
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

        private init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }

        /// This cell plus the 8 around it, for tolerant live matching.
        var selfAndNeighbours: [GridKey] {
            (-1...1).flatMap { dy in
                (-1...1).map { dx in GridKey(x: x + dx, y: y + dy) }
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

    static func build(from runs: [RouteRun]) -> RouteGraph {
        var graph = RouteGraph()
        for run in runs {
            let path = cellPath(for: run)
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
        return graph
    }

    /// The branches at this cell for someone arriving on this heading —
    /// empty unless the cell is genuinely a decision point (two or more
    /// trusted branches). Conditioning on approach keeps the outbound and
    /// homebound passes through the same physical corner separate.
    func branches(at key: GridKey, approachBearing: Double) -> [Branch] {
        guard let traversals = nodes[key] else { return [] }
        let matching = traversals.filter {
            Self.angularDistance($0.approachBearing, approachBearing) <= 75
        }
        guard matching.count >= Self.minimumSamplesPerBranch * 2 else { return [] }

        let clusters = Self.clusterBearings(matching.map(\.outgoingBearing))
        let branches: [Branch] = clusters.compactMap { memberIndices in
            guard memberIndices.count >= Self.minimumSamplesPerBranch else { return nil }
            let members = memberIndices.map { matching[$0] }
            return Branch(
                bearing: Self.circularMean(members.map(\.outgoingBearing)),
                expectedRemainingSeconds: members.map(\.remainingSeconds).reduce(0, +) / Double(members.count),
                expectedRemainingEnergy: members.map(\.remainingEnergy).reduce(0, +) / Double(members.count),
                sampleCount: members.count,
                probability: Double(members.count) / Double(matching.count)
            )
        }
        return branches.count >= 2 ? branches.sorted { $0.probability > $1.probability } : []
    }

    // MARK: - Track → cell path

    private struct CellStep {
        var key: GridKey
        var point: TrackPoint
        var outgoingBearing: Double?
    }

    private static func cellPath(for run: RouteRun) -> [CellStep] {
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

    /// Groups bearings into clusters no wider apart than
    /// `clusterWidthDegrees`, respecting the 0°/360° wrap. Returns index
    /// groups into the input array.
    static func clusterBearings(_ bearings: [Double]) -> [[Int]] {
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
            if gap <= clusterWidthDegrees {
                clusters[clusters.count - 1].append(rotated[position])
            } else {
                clusters.append([rotated[position]])
            }
        }
        return clusters
    }
}
