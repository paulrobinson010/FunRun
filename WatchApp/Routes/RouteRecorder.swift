import CoreLocation
import Foundation
import Observation

/// Records the session's GPS track, thinned to roughly one point per
/// 8 metres, each stamped with the session's distance and energy at that
/// moment. Also the live position/heading feed for intersection lookups.
@MainActor
@Observable
final class RouteRecorder: NSObject, CLLocationManagerDelegate {
    private(set) var points: [TrackPoint] = []
    /// Every accurate fix, unthinned — feeds the HealthKit workout route
    /// so the Fitness app can draw the map.
    private(set) var rawLocations: [CLLocation] = []
    private(set) var lastLocation: CLLocation?

    /// Supplied by WorkoutManager so each point carries the workout state.
    var metrics: (() -> (distance: Double, energy: Double))?

    private let manager = CLLocationManager()
    private var sessionStart = Date()
    private let minimumSpacingMeters: Double = 8
    private let accuracyLimitMeters: Double = 35

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    func start(at date: Date) {
        sessionStart = date
        points = []
        rawLocations = []
        lastLocation = nil
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    /// Current travel direction in degrees, if GPS has one.
    var course: Double? {
        guard let course = lastLocation?.course, course >= 0 else { return nil }
        return course
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                self.ingest(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func ingest(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= accuracyLimitMeters else { return }
        lastLocation = location
        rawLocations.append(location)
        if let last = points.last {
            let previous = CLLocation(latitude: last.latitude, longitude: last.longitude)
            guard location.distance(from: previous) >= minimumSpacingMeters else { return }
        }
        let state = metrics?() ?? (0, 0)
        points.append(TrackPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elapsed: location.timestamp.timeIntervalSince(sessionStart),
            distanceMeters: state.distance,
            energyKilocalories: state.energy
        ))
    }
}
