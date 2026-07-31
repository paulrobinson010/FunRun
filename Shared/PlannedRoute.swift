import Foundation

/// A route built on the phone from the learned network — an ordered
/// chain of fork-to-fork legs — and followed on the watch: the forks
/// page becomes turn-by-turn, with distance to go and an overall ±.
struct PlannedRoute: Codable, Equatable {
    struct Leg: Codable, Equatable {
        var from: RouteGraph.GridKey
        var to: RouteGraph.GridKey
        /// The direction this leg leaves `from` in — the turn arrow.
        var exitBearing: Double
        var distanceMeters: Double
        /// Typical time over this stretch from history (average pace
        /// fallback where the stretch has no fork-to-fork timing).
        var expectedSeconds: TimeInterval
    }

    var id: UUID = UUID()
    var createdAt: Date = Date()
    var legs: [Leg]

    var totalMeters: Double { legs.reduce(0) { $0 + $1.distanceMeters } }
    var totalSeconds: TimeInterval { legs.reduce(0) { $0 + $1.expectedSeconds } }
}
