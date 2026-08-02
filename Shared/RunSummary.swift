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
    /// Active energy for the outing, as HealthKit measured it.
    var activeEnergyKilocalories: Double? = nil
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
    /// GPS fixes kept and turned away by the accuracy gate. Diagnostic:
    /// a short map with a healthy accepted count means the thinning or
    /// the transfer lost it; a low accepted count means the watch never
    /// got the fixes.
    var gpsFixesAccepted: Int? = nil
    var gpsFixesRejected: Int? = nil
    /// Walking effort 1–10, only when the outing had both walking and
    /// running and they were scored separately — `effort` is then the
    /// running score.
    var walkEffort: Int? = nil

    var distanceKm: Double { distanceMeters / 1000 }

    /// Rounded for display; nil when the workout recorded no energy
    /// (older runs saved before energy was carried, or a session
    /// HealthKit gave nothing for).
    var kilocalories: Int? {
        guard let activeEnergyKilocalories, activeEnergyKilocalories >= 1 else { return nil }
        return Int(activeEnergyKilocalories.rounded())
    }

    var averagePaceSecondsPerKm: Double? {
        guard distanceMeters > 50, activeSeconds > 0 else { return nil }
        return activeSeconds / distanceKm
    }

    func distance(in mode: ActivityMode) -> Double {
        segments.filter { $0.mode == mode }.reduce(0) { $0 + $1.distanceMeters }
    }

    /// Overall pace while in one mode. Segments carry wall-clock spans
    /// (pauses included), so each mode's share of the moving time is
    /// taken proportionally — pauses come off both modes evenly. Nil
    /// when the mode covered too little ground to give an honest pace.
    func averagePaceSecondsPerKm(in mode: ActivityMode) -> Double? {
        let modeMeters = distance(in: mode)
        guard modeMeters > 100, activeSeconds > 0 else { return nil }
        let wallTotal = segments.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let wallMode = segments.filter { $0.mode == mode }
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        guard wallTotal > 0, wallMode > 0 else { return nil }
        let movingSeconds = activeSeconds * (wallMode / wallTotal)
        return movingSeconds / (modeMeters / 1000)
    }
}
