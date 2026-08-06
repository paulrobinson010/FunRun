import CoreLocation
import Foundation

/// What the wrist shows approaching a known intersection: each way
/// you've gone before, as a direction relative to how you're moving
/// right now — the stretch it leads onto, the pace to beat on it, and
/// the quickest you could be home going that way.
struct RoutePrediction: Equatable {
    struct Choice: Equatable, Identifiable {
        var id: Int
        var direction: RelativeDirection
        /// Length of the stretch to the next fork, going this way.
        var distanceMeters: Double?
        /// Fastest pace over that stretch in the comparison window —
        /// the time to beat. Nil when it hasn't been run recently.
        var bestPaceSecondsPerKm: Double?
        /// Quickest known time home setting off this way: your best
        /// time on each leg of the fastest route, chained.
        var homeSeconds: TimeInterval?
        /// How often past runs went this way from here.
        var probabilityPercent: Int
        var sampleCount: Int
    }

    /// Which grid cell produced this prediction — used to notice
    /// approaching a *new* intersection vs. lingering near one.
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
    /// All-history segment index, for routing and for branch lengths on
    /// stretches not run inside the comparison window.
    private let routing: SegmentIndex
    /// Where runs usually end, and the fastest known way there from each
    /// fork: seconds home + which way to set off.
    private let homeCoordinate: CLLocationCoordinate2D?
    private let homeCells: Set<RouteGraph.GridKey>
    private let homeRoute: [RouteGraph.GridKey: (seconds: TimeInterval, exitBearing: Double)]

    /// Median historical speed per cell, from the comparison window —
    /// "how fast do I usually cover this exact ground". Feeds the km
    /// split's vs-history delta.
    private let speedField: [RouteGraph.GridKey: Double]

    /// Your usual speed at this spot, or nil where you've never run.
    func referenceSpeed(at coordinate: CLLocationCoordinate2D) -> Double? {
        var speeds: [Double] = []
        for cell in RouteGraph.GridKey(coordinate).selfAndNeighbours {
            if let speed = speedField[cell] {
                speeds.append(speed)
            }
        }
        guard !speeds.isEmpty else { return nil }
        return speeds.sorted()[speeds.count / 2]
    }

    init(runs: [RouteRun]) {
        graph = RouteGraph.build(from: runs)
        let cutoff = Date().addingTimeInterval(-Double(Self.comparisonWindowDays) * 86_400)
        let windowRuns = runs.filter { $0.date >= cutoff }
        segments = SegmentIndex.build(from: windowRuns, graph: graph)

        var field: [RouteGraph.GridKey: [Double]] = [:]
        for run in windowRuns {
            for index in 0..<max(0, run.points.count - 1) {
                let a = run.points[index]
                let b = run.points[index + 1]
                let dt = b.elapsed - a.elapsed
                let dd = b.distanceMeters - a.distanceMeters
                guard dt > 0.5, dd > 1 else { continue }
                let speed = dd / dt
                guard speed > 0.3, speed < 9 else { continue }
                let cell = RouteGraph.GridKey(CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude))
                field[cell, default: []].append(speed)
            }
        }
        speedField = field.mapValues { speeds in
            speeds.sorted()[speeds.count / 2]
        }

        // Home = the cell most runs finish in; routing uses all stored
        // history, not just the comparison window — the way home doesn't
        // go stale the way pace does.
        routing = SegmentIndex.build(from: runs, graph: graph)
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
            homeCells = Set(homeCell.selfAndNeighbours)
            homeRoute = Self.buildHomeRoute(edges: routing.edges, home: homeCell)
        } else {
            homeCoordinate = nil
            homeCells = []
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
        for candidate in key.neighbours(radius: 2) {
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

    /// The fork actually being passed right now — within ~2 cells of the
    /// current position, no lookahead. Segment timing keys off this, so
    /// live segments match how history was carved up.
    func arrivalNode(at coordinate: CLLocationCoordinate2D) -> RouteGraph.GridKey? {
        RouteGraph.GridKey(coordinate).neighbours(radius: 2).first(where: graph.decisionCells.contains)
    }

    /// Length of the segment leaving `fork` in the direction you left
    /// it — how "1.2 km segment" pairs with "800 m covered" to give a
    /// to-go figure. Recent history first, all history as fallback.
    func branchLengthMeters(from fork: RouteGraph.GridKey, exitBearing: Double) -> Double? {
        segments.branchStats(from: fork, startBearing: exitBearing)?.medianMeters
            ?? routing.branchStats(from: fork, startBearing: exitBearing)?.medianMeters
    }

    /// Quickest known time home setting off from this fork in this
    /// direction: your best recorded time to the next fork that way,
    /// plus the fastest chain of bests from there.
    private func quickestHome(from fork: RouteGraph.GridKey, viaBearing: Double) -> TimeInterval? {
        guard homeCoordinate != nil else { return nil }
        var best: TimeInterval?
        for edge in routing.traversals(from: fork)
        where RouteGraph.angularDistance(edge.startBearing, viaBearing) <= RouteGraph.clusterWidthDegrees {
            let onward = homeCells.contains(edge.to) ? 0 : homeRoute[edge.to]?.seconds
            guard let onward else { continue }
            best = min(best ?? .infinity, edge.seconds + onward)
        }
        return best
    }

    /// The prediction fires from ~50 m out, but only for a fork you're
    /// actually heading towards — the position is projected forward
    /// along the course, not just widened. Each probe also matches
    /// within ~2 cells, so the effective reach runs a little past the
    /// last step.
    private static let lookaheadMeters: [Double] = [0, 18, 36]

    func prediction(at location: CLLocation, course: Double) -> RoutePrediction? {
        for ahead in Self.lookaheadMeters {
            let probe = Self.project(location.coordinate, bearing: course, meters: ahead)
            for candidate in RouteGraph.GridKey(probe).neighbours(radius: 2) {
                let branches = graph.branches(at: candidate, course: course)
                guard branches.count >= 2 else { continue }
                let choices = branches.enumerated().map { index, branch -> RoutePrediction.Choice in
                    // Length from the window when the stretch was run
                    // recently, else from all history; the pace to beat
                    // only ever from the window.
                    let recent = segments.branchStats(from: candidate, startBearing: branch.bearing)
                    let ever = routing.branchStats(from: candidate, startBearing: branch.bearing)
                    return RoutePrediction.Choice(
                        id: index,
                        direction: RelativeDirection(course: course, branchBearing: branch.bearing),
                        distanceMeters: recent?.medianMeters ?? ever?.medianMeters,
                        bestPaceSecondsPerKm: recent?.bestSecondsPerKm,
                        homeSeconds: quickestHome(from: candidate, viaBearing: branch.bearing),
                        probabilityPercent: Int((branch.probability * 100).rounded()),
                        sampleCount: branch.sampleCount
                    )
                }
                return RoutePrediction(nodeKey: candidate, choices: choices)
            }
        }
        return nil
    }

    private static func project(_ coordinate: CLLocationCoordinate2D, bearing: Double, meters: Double) -> CLLocationCoordinate2D {
        guard meters > 0 else { return coordinate }
        let radians = bearing * .pi / 180
        let deltaLatitude = cos(radians) * meters / 111_320
        let deltaLongitude = sin(radians) * meters / (111_320 * cos(coordinate.latitude * .pi / 180))
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + deltaLatitude,
            longitude: coordinate.longitude + deltaLongitude
        )
    }
}
