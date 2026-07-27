import CoreLocation
import Foundation

/// Recognises when two recorded runs are the same physical route, so a
/// favourite means "the route" rather than one day's recording: racing a
/// favourite automatically races your fastest matching attempt.
enum RouteMatcher {
    /// Two runs match when their distances are within ~12% and their
    /// grid-cell footprints mostly overlap.
    static let distanceTolerance = 0.12
    static let minimumOverlap = 0.65

    /// The fastest stored run of the same route — the given run itself
    /// if nothing quicker matches.
    static func fastestMatch(for route: RouteRun, in runs: [RouteRun]) -> RouteRun {
        let targetCells = cellSet(route)
        guard !targetCells.isEmpty else { return route }
        var best = route
        for candidate in runs where candidate.id != route.id {
            guard abs(candidate.totalDistanceMeters - route.totalDistanceMeters)
                    <= route.totalDistanceMeters * distanceTolerance,
                  candidate.totalSeconds < best.totalSeconds else { continue }
            let cells = cellSet(candidate)
            let overlap = Double(cells.intersection(targetCells).count)
            let union = Double(cells.union(targetCells).count)
            guard union > 0, overlap / union >= minimumOverlap else { continue }
            best = candidate
        }
        return best
    }

    private static func cellSet(_ run: RouteRun) -> Set<RouteGraph.GridKey> {
        Set(run.points.map {
            RouteGraph.GridKey(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
        })
    }
}
