import CoreLocation
import Foundation

/// What the wrist shows at a known intersection: each way you've gone
/// before, as a direction relative to how you're moving right now, with
/// the expected outcome of choosing it.
struct RoutePrediction: Equatable {
    struct Choice: Equatable, Identifiable {
        var id: Int
        var direction: RelativeDirection
        /// Expected minutes until the session ends, going this way.
        var finishInMinutes: Int
        /// Burned so far + expected burn for the rest, going this way.
        var totalCalories: Int
        /// How often past runs went this way from here.
        var probabilityPercent: Int
        var sampleCount: Int
        /// Expected time from here to the next fork, going this way —
        /// from the comparison window, when it has enough passes.
        var nextForkSeconds: TimeInterval?
    }

    /// Which grid cell produced this prediction — used to notice arriving
    /// at a *new* intersection (for the haptic) vs. lingering at one.
    var nodeKey: RouteGraph.GridKey
    var choices: [Choice]
}

enum RelativeDirection: Equatable {
    case straight
    case left
    case right
    case uTurn

    init(course: Double, branchBearing: Double) {
        let delta = (branchBearing - course + 360).truncatingRemainder(dividingBy: 360)
        switch delta {
        case ..<40, 320...: self = .straight
        case 40..<160: self = .right
        case 160..<200: self = .uTurn
        default: self = .left
        }
    }

    var symbolName: String {
        switch self {
        case .straight: "arrow.up"
        case .left: "arrow.turn.up.left"
        case .right: "arrow.turn.up.right"
        case .uTurn: "arrow.uturn.down"
        }
    }

    var label: String {
        switch self {
        case .straight: "Ahead"
        case .left: "Left"
        case .right: "Right"
        case .uTurn: "Back"
        }
    }
}

/// How a just-finished segment (previous fork → this one) compares to the
/// recent history of the same stretch.
struct SegmentComparison: Equatable {
    var seconds: TimeInterval
    /// This pass minus the window average; negative means faster. Nil
    /// when the stretch has no recent history to compare against.
    var deltaSeconds: TimeInterval?
    /// True when this pass beat every recent pass of the stretch.
    var isBest: Bool
    var sampleCount: Int
    var at: Date
}

/// Built once per session from route history; answers "am I at a known
/// decision point, and what does each choice cost?" every tick.
/// Immutable after construction, so it can be built off the main actor —
/// a year of tracks takes real work — and handed over when ready.
final class RoutePredictor: Sendable {
    /// Segment comparisons ("vs typical", "to next fork") only look this
    /// far back, so they track current fitness; the decision-point graph
    /// itself uses all stored history.
    static let comparisonWindowDays = 28

    private let graph: RouteGraph
    private let segments: SegmentIndex

    init(runs: [RouteRun]) {
        graph = RouteGraph.build(from: runs)
        let cutoff = Date().addingTimeInterval(-Double(Self.comparisonWindowDays) * 86_400)
        segments = SegmentIndex.build(from: runs.filter { $0.date >= cutoff }, graph: graph)
    }

    /// Comparison for the segment just completed, against the window.
    func segmentComparison(from: RouteGraph.GridKey, to: RouteGraph.GridKey, seconds: TimeInterval) -> SegmentComparison {
        let stats = segments.stats(from: from, to: to)
        return SegmentComparison(
            seconds: seconds,
            deltaSeconds: stats.map { seconds - $0.averageSeconds },
            isBest: stats.map { seconds < $0.bestSeconds } ?? false,
            sampleCount: stats?.count ?? 0,
            at: Date()
        )
    }

    func prediction(at location: CLLocation, course: Double, energySoFar: Double) -> RoutePrediction? {
        let key = RouteGraph.GridKey(location.coordinate)
        for candidate in key.selfAndNeighbours {
            let branches = graph.branches(at: candidate, approachBearing: course)
            guard branches.count >= 2 else { continue }
            let choices = branches.enumerated().map { index, branch in
                RoutePrediction.Choice(
                    id: index,
                    direction: RelativeDirection(course: course, branchBearing: branch.bearing),
                    finishInMinutes: max(1, Int((branch.expectedRemainingSeconds / 60).rounded())),
                    totalCalories: Int((energySoFar + branch.expectedRemainingEnergy).rounded()),
                    probabilityPercent: Int((branch.probability * 100).rounded()),
                    sampleCount: branch.sampleCount,
                    nextForkSeconds: segments.expectedSeconds(from: candidate, startBearing: branch.bearing)
                )
            }
            return RoutePrediction(nodeKey: candidate, choices: choices)
        }
        return nil
    }
}
