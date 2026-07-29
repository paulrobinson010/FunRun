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
        /// True on the branch whose expected finish lands closest to the
        /// session's target time, when one was set.
        var isRecommended: Bool = false
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

/// Live guidance toward the usual finishing spot.
struct HomeGuidance: Equatable {
    var direction: RelativeDirection
    /// Fastest known time home from this fork; nil between forks, where
    /// only the as-the-crow-flies arrow is available.
    var etaSeconds: TimeInterval?
    var atFork: Bool

    var etaMinutes: Int? {
        etaSeconds.map { max(1, Int(($0 / 60).rounded())) }
    }
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
    /// Overall wall-clock speed across the stored history, for scaling
    /// predictions to how today is actually going.
    private let historicalAverageSpeed: Double?
    /// Where runs usually end, and the fastest known way there from each
    /// fork: seconds home + which way to set off.
    private let homeCoordinate: CLLocationCoordinate2D?
    private let homeRoute: [RouteGraph.GridKey: (seconds: TimeInterval, exitBearing: Double)]

    init(runs: [RouteRun]) {
        graph = RouteGraph.build(from: runs)
        let cutoff = Date().addingTimeInterval(-Double(Self.comparisonWindowDays) * 86_400)
        segments = SegmentIndex.build(from: runs.filter { $0.date >= cutoff }, graph: graph)
        let totalMeters = runs.reduce(0) { $0 + $1.totalDistanceMeters }
        let totalSeconds = runs.reduce(0) { $0 + $1.totalSeconds }
        historicalAverageSpeed = (totalMeters > 1000 && totalSeconds > 0) ? totalMeters / totalSeconds : nil

        // Home = the cell most runs finish in; routing uses all stored
        // history, not just the comparison window — the way home doesn't
        // go stale the way pace does.
        let endings = runs.compactMap(\.points.last)
        let endCells = Dictionary(grouping: endings) {
            RouteGraph.GridKey(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
        }
        if let (homeCell, homeEndings) = endCells.max(by: { $0.value.count < $1.value.count }),
           homeEndings.count >= 2 {
            homeCoordinate = CLLocationCoordinate2D(
                latitude: homeEndings.map(\.latitude).reduce(0, +) / Double(homeEndings.count),
                longitude: homeEndings.map(\.longitude).reduce(0, +) / Double(homeEndings.count)
            )
            let routing = SegmentIndex.build(from: runs, graph: graph)
            homeRoute = Self.buildHomeRoute(edges: routing.edges, home: homeCell)
        } else {
            homeCoordinate = nil
            homeRoute = [:]
        }
    }

    /// Shortest-known-time-to-home from every fork, by relaxing the
    /// segment edges backwards from home until stable.
    private static func buildHomeRoute(
        edges: [(from: RouteGraph.GridKey, to: RouteGraph.GridKey, startBearing: Double, seconds: TimeInterval)],
        home: RouteGraph.GridKey
    ) -> [RouteGraph.GridKey: (seconds: TimeInterval, exitBearing: Double)] {
        let homeCells = Set(home.selfAndNeighbours)
        var route: [RouteGraph.GridKey: (seconds: TimeInterval, exitBearing: Double)] = [home: (0, 0)]
        var changed = true
        var iterations = 0
        while changed && iterations < 100 {
            changed = false
            iterations += 1
            for edge in edges {
                let destination = homeCells.contains(edge.to) ? home : edge.to
                guard let toHome = route[destination]?.seconds else { continue }
                let candidate = toHome + edge.seconds
                if candidate < (route[edge.from]?.seconds ?? .infinity) - 1 {
                    route[edge.from] = (candidate, edge.startBearing)
                    changed = true
                }
            }
        }
        return route
    }

    /// Which way home, from here: at a known fork, the first leg of the
    /// fastest known path plus its ETA; between forks, a plain arrow
    /// toward the finish.
    func homeGuidance(at location: CLLocation, course: Double) -> HomeGuidance? {
        guard let homeCoordinate else { return nil }
        let key = RouteGraph.GridKey(location.coordinate)
        for candidate in key.selfAndNeighbours {
            if let entry = homeRoute[candidate], entry.seconds > 0 {
                return HomeGuidance(
                    direction: RelativeDirection(course: course, branchBearing: entry.exitBearing),
                    etaSeconds: entry.seconds,
                    atFork: true
                )
            }
        }
        let here = TrackPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elapsed: 0, distanceMeters: 0, energyKilocalories: 0
        )
        let there = TrackPoint(
            latitude: homeCoordinate.latitude,
            longitude: homeCoordinate.longitude,
            elapsed: 0, distanceMeters: 0, energyKilocalories: 0
        )
        return HomeGuidance(
            direction: RelativeDirection(course: course, branchBearing: RouteGraph.bearing(from: here, to: there)),
            etaSeconds: nil,
            atFork: false
        )
    }

    /// A slow day honestly predicts slower finishes: expected times are
    /// scaled by historical speed ÷ today's, clamped so one bad
    /// kilometre doesn't distort the whole forecast. Calories stay
    /// unscaled — they track distance far more than pace.
    private func paceFactor(currentAverageSpeed: Double?) -> Double {
        guard let historicalAverageSpeed, let currentAverageSpeed, currentAverageSpeed > 0.3 else { return 1 }
        return min(1.3, max(0.75, historicalAverageSpeed / currentAverageSpeed))
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

    func prediction(
        at location: CLLocation,
        course: Double,
        energySoFar: Double,
        currentAverageSpeed: Double? = nil,
        elapsedSeconds: TimeInterval = 0,
        targetSeconds: TimeInterval? = nil
    ) -> RoutePrediction? {
        let factor = paceFactor(currentAverageSpeed: currentAverageSpeed)
        let key = RouteGraph.GridKey(location.coordinate)
        for candidate in key.selfAndNeighbours {
            let branches = graph.branches(at: candidate, course: course)
            guard branches.count >= 2 else { continue }
            var choices = branches.enumerated().map { index, branch in
                RoutePrediction.Choice(
                    id: index,
                    direction: RelativeDirection(course: course, branchBearing: branch.bearing),
                    finishInMinutes: max(1, Int((branch.expectedRemainingSeconds * factor / 60).rounded())),
                    totalCalories: Int((energySoFar + branch.expectedRemainingEnergy).rounded()),
                    probabilityPercent: Int((branch.probability * 100).rounded()),
                    sampleCount: branch.sampleCount,
                    nextForkSeconds: segments.expectedSeconds(from: candidate, startBearing: branch.bearing).map { $0 * factor }
                )
            }
            // With a target session length set, star the branch whose
            // expected finish lands closest to it.
            if let targetSeconds {
                let recommended = branches.indices.min { a, b in
                    let missA = abs(elapsedSeconds + branches[a].expectedRemainingSeconds * factor - targetSeconds)
                    let missB = abs(elapsedSeconds + branches[b].expectedRemainingSeconds * factor - targetSeconds)
                    return missA < missB
                }
                if let recommended {
                    choices[recommended].isRecommended = true
                }
            }
            return RoutePrediction(nodeKey: candidate, choices: choices)
        }
        return nil
    }
}
