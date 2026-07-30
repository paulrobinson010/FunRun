import Foundation

/// One contiguous stretch of walking or running within a session.
struct RunSegment: Codable, Hashable {
    var mode: ActivityMode
    var start: Date
    var end: Date
    var distanceMeters: Double
}

/// A finished session as the app records it — created on the watch when a
/// workout ends and synced to the phone, where it drives history and shoe
/// wear. The HealthKit workout itself is saved separately on the watch.
struct RunSummary: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var startDate: Date
    var endDate: Date
    /// Moving time — pauses (manual and auto) excluded.
    var activeSeconds: TimeInterval
    var distanceMeters: Double
    var averageHeartRate: Double?
    /// Perceived effort 1–10, asked for at the end of the session.
    var effort: Int?
    var shoeID: UUID?
    var shoeName: String?
    var segments: [RunSegment]
    var autoPauseCount: Int
    /// How the session was written to HealthKit: one entry per saved
    /// workout. Several entries mean the outing was chained into separate
    /// walk and run workouts; a single entry means it stayed one workout.
    var savedWorkouts: [RunSegment]? = nil
    /// The route, thinned for drawing on the phone's map (~20 m spacing).
    var track: [TrackPoint]? = nil
    /// Walking effort 1–10, only when the outing had both walking and
    /// running and they were scored separately — `effort` is then the
    /// running score.
    var walkEffort: Int? = nil

    var distanceKm: Double { distanceMeters / 1000 }

    var averagePaceSecondsPerKm: Double? {
        guard distanceMeters > 50, activeSeconds > 0 else { return nil }
        return activeSeconds / distanceKm
    }

    func distance(in mode: ActivityMode) -> Double {
        segments.filter { $0.mode == mode }.reduce(0) { $0 + $1.distanceMeters }
    }
}
