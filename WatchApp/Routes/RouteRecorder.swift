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

    /// How many fixes were kept and how many the accuracy gate turned
    /// away — carried on the finished run so a short track can be told
    /// apart from a track that never got fixes at all.
    private(set) var acceptedFixes = 0
    private(set) var rejectedFixes = 0

    private let manager = CLLocationManager()
    private var sessionStart = Date()
    private var isRecording = false
    private let minimumSpacingMeters: Double = 8
    /// Normal gate. A walk with the wrist down gets noticeably coarser
    /// fixes than a run, so holding out for 35 m can starve the track
    /// while HealthKit — which fuses the pedometer — keeps counting
    /// distance quite happily.
    private let accuracyLimitMeters: Double = 35
    /// After this long with nothing accepted, take the best on offer up
    /// to `relaxedAccuracyMeters`: a coarse fix beats a gap in the line.
    private let starvedAfterSeconds: TimeInterval = 25
    private let relaxedAccuracyMeters: Double = 100
    private var lastAcceptedAt: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    /// Ask once, up front, while the app is settled in the foreground —
    /// asking in the same breath as starting a workout is what makes
    /// grants not stick and prompts reappear.
    func requestPermissionIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    private var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
    }

    func start(at date: Date) {
        sessionStart = date
        points = []
        rawLocations = []
        lastLocation = nil
        acceptedFixes = 0
        rejectedFixes = 0
        lastAcceptedAt = nil
        isRecording = true
        requestPermissionIfNeeded()
        // Only opt into background updates once actually authorised —
        // flipping it pre-grant makes the system re-litigate permission.
        if isAuthorized {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        isRecording = false
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorized = manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
        Task { @MainActor in
            // Granted mid-session (first-ever run): turn background
            // updates on now that it's allowed.
            if authorized, self.isRecording {
                self.manager.allowsBackgroundLocationUpdates = true
            }
        }
    }

    private func ingest(_ location: CLLocation) {
        let starved = lastAcceptedAt.map { Date().timeIntervalSince($0) > starvedAfterSeconds } ?? false
        let limit = starved ? relaxedAccuracyMeters : accuracyLimitMeters
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= limit else {
            rejectedFixes += 1
            return
        }
        acceptedFixes += 1
        lastAcceptedAt = Date()
        lastLocation = location
        rawLocations.append(location)
        if let last = points.last {
            let previous = CLLocation(latitude: last.latitude, longitude: last.longitude)
            guard location.distance(from: previous) >= minimumSpacingMeters else { return }
        }
        let state = metrics?() ?? (distance: 0, energy: 0)
        points.append(TrackPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elapsed: location.timestamp.timeIntervalSince(sessionStart),
            distanceMeters: state.distance,
            energyKilocalories: state.energy
        ))
    }
}
