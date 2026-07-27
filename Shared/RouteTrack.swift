import Foundation

/// One thinned GPS fix from a session, with the session state at that
/// moment — enough to later answer "when I was here, how much time and
/// energy was still to come?"
struct TrackPoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    /// Wall-clock seconds since the session started (pauses included —
    /// "back in 25 minutes" means real minutes).
    var elapsed: TimeInterval
    var distanceMeters: Double
    var energyKilocalories: Double
}

/// A finished session's route, kept on the watch as the raw material for
/// intersection predictions.
struct RouteRun: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    /// Wall-clock length of the whole session.
    var totalSeconds: TimeInterval
    var totalEnergyKilocalories: Double
    var points: [TrackPoint]
}
