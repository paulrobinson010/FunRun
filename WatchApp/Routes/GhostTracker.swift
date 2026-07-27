import CoreLocation
import Foundation

/// Where you stand against the ghost right now.
struct GhostStatus: Equatable {
    enum State: Equatable {
        case onRoute
        case offRoute
        case finished
    }

    var state: State
    /// Ghost's elapsed at this point minus yours — positive means you got
    /// here sooner than the ghost did.
    var deltaSeconds: TimeInterval
    var remainingMeters: Double
    /// Upcoming guidance while on route: which way the route bends ahead.
    var turn: RelativeDirection?
    /// When off route: which way back to it, and how far.
    var directionToRoute: RelativeDirection?
    var metersToRoute: Double?
}

/// Replays a past run as a ghost. Matches the live position onto the
/// ghost's track — monotonically, with a small backward allowance, so an
/// out-and-back route doesn't snap you onto the homeward leg while you're
/// still outbound. Drifting outside the corridor flips to
/// find-my-way-back mode; re-entering it anywhere rejoins the route there.
@MainActor
final class GhostTracker {
    let route: RouteRun

    private var matchedIndex = 0
    /// How far off the track still counts as "on the route".
    private let corridorMeters: Double = 75
    /// Guidance looks this far ahead along the route.
    private let lookaheadMeters: Double = 80
    private let windowBack = 5
    private let windowForward = 80

    init(route: RouteRun) {
        self.route = route
    }

    func update(location: CLLocation, course: Double?, wallElapsed: TimeInterval) -> GhostStatus? {
        let points = route.points
        guard points.count >= 2 else { return nil }

        let lower = max(0, matchedIndex - windowBack)
        let upper = min(points.count - 1, matchedIndex + windowForward)
        var best = (index: matchedIndex, meters: Double.greatestFiniteMagnitude)
        for index in lower...upper {
            let meters = distance(from: location, to: points[index])
            if meters < best.meters {
                best = (index, meters)
            }
        }

        if best.meters > corridorMeters {
            // Lost the corridor — search the whole route: either we've
            // rejoined it somewhere unexpected, or we're genuinely off it
            // and the nearest point is the way back.
            var globalBest = best
            for index in points.indices {
                let meters = distance(from: location, to: points[index])
                if meters < globalBest.meters {
                    globalBest = (index, meters)
                }
            }
            if globalBest.meters <= corridorMeters {
                matchedIndex = globalBest.index
            } else {
                let bearingBack = bearing(from: location, to: points[globalBest.index])
                return GhostStatus(
                    state: .offRoute,
                    deltaSeconds: points[matchedIndex].elapsed - wallElapsed,
                    remainingMeters: remainingMeters(at: matchedIndex),
                    turn: nil,
                    directionToRoute: course.map { RelativeDirection(course: $0, branchBearing: bearingBack) },
                    metersToRoute: globalBest.meters
                )
            }
        } else {
            matchedIndex = best.index
        }

        if matchedIndex >= points.count - 3 {
            return GhostStatus(
                state: .finished,
                deltaSeconds: route.totalSeconds - wallElapsed,
                remainingMeters: 0,
                turn: nil,
                directionToRoute: nil,
                metersToRoute: nil
            )
        }

        let turn = course.flatMap { course -> RelativeDirection? in
            guard let target = lookaheadPoint(from: matchedIndex) else { return nil }
            return RelativeDirection(course: course, branchBearing: bearing(from: location, to: target))
        }
        return GhostStatus(
            state: .onRoute,
            deltaSeconds: route.points[matchedIndex].elapsed - wallElapsed,
            remainingMeters: remainingMeters(at: matchedIndex),
            turn: turn,
            directionToRoute: nil,
            metersToRoute: nil
        )
    }

    // MARK: - Helpers

    private func distance(from location: CLLocation, to point: TrackPoint) -> Double {
        location.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
    }

    private func bearing(from location: CLLocation, to point: TrackPoint) -> Double {
        let here = TrackPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elapsed: 0,
            distanceMeters: 0,
            energyKilocalories: 0
        )
        return RouteGraph.bearing(from: here, to: point)
    }

    private func lookaheadPoint(from index: Int) -> TrackPoint? {
        let targetDistance = route.points[index].distanceMeters + lookaheadMeters
        return route.points[index...].first { $0.distanceMeters >= targetDistance } ?? route.points.last
    }

    private func remainingMeters(at index: Int) -> Double {
        max(0, route.totalDistanceMeters - route.points[index].distanceMeters)
    }
}
