import Foundation

/// Screenshot/demo mode: launch with the `-demo` argument (add it to an
/// Xcode scheme) and both apps present seeded example data instead of
/// real state. Debug builds only — release builds compile this to
/// `false`, so demo can never reach TestFlight or the App Store.
///
/// Demo data is strictly in-memory: nothing is persisted, synced, or
/// written to HealthKit.
enum DemoMode {
    static var isActive: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        false
        #endif
    }
}

/// The example data both apps present in demo mode — plausible numbers,
/// not aspirational ones.
enum DemoData {
    static let shoes: [Shoe] = [
        Shoe(name: "Pegasus 41", brand: "Nike", replaceAfterKm: 650, distanceMeters: 318_000, color: "Blue"),
        Shoe(name: "Clifton 9", brand: "Hoka", replaceAfterKm: 650, distanceMeters: 586_000, color: "White"),
        Shoe(name: "Adizero SL", brand: "Adidas", replaceAfterKm: 600, distanceMeters: 611_000, retired: true, color: "Multicolour"),
    ]

    /// Three weeks of history: mixed distances and efforts, a chained
    /// walk/run/walk outing, and tracks that draw as organic loops on
    /// the map. This week's load sits a little above the recent average
    /// so the training-load card has something to say.
    static var runs: [RunSummary] {
        let plans: [(daysAgo: Double, km: Double, paceSecPerKm: Double, effort: Int?, shoe: Int)] = [
            (0.3, 7.2, 355, 6, 0), (2, 5.1, 340, 7, 1),
            (4, 10.4, 372, 8, 0), (6, 4.0, 400, 3, 1),
            (9, 7.5, 362, 5, 0), (11, 5.0, 348, 6, 1),
            (13, 8.1, 368, 7, 0), (16, 6.4, 358, 5, 1),
            (19, 5.2, 351, 6, 0), (21, 9.6, 377, 8, 0),
        ]
        return plans.enumerated().map { index, plan in
            let distance = plan.km * 1000
            let moving = distance / 1000 * plan.paceSecPerKm
            let start = Date().addingTimeInterval(-plan.daysAgo * 86_400 - moving)
            let end = start.addingTimeInterval(moving * 1.03)
            let segments: [RunSegment]
            var savedWorkouts: [RunSegment]?
            if index == 2 {
                // The signature chained outing: walk, run, walk.
                let walkOut = RunSegment(mode: .walking, start: start, end: start.addingTimeInterval(moving * 0.2), distanceMeters: distance * 0.18)
                let run = RunSegment(mode: .running, start: walkOut.end, end: start.addingTimeInterval(moving * 0.75), distanceMeters: distance * 0.62)
                let walkBack = RunSegment(mode: .walking, start: run.end, end: end, distanceMeters: distance * 0.2)
                segments = [walkOut, run, walkBack]
                savedWorkouts = segments
            } else {
                segments = [RunSegment(mode: .running, start: start, end: end, distanceMeters: distance)]
                savedWorkouts = segments
            }
            return RunSummary(
                startDate: start,
                endDate: end,
                activeSeconds: moving,
                distanceMeters: distance,
                averageHeartRate: Double(138 + (index * 7) % 26),
                effort: plan.effort,
                shoeID: shoes[plan.shoe].id,
                shoeName: shoes[plan.shoe].displayName,
                segments: segments,
                autoPauseCount: index % 3,
                savedWorkouts: savedWorkouts,
                track: loopTrack(distance: distance, duration: moving, seed: index)
            )
        }
    }

    /// An organic-looking loop for the map: a wobbled circle sized so
    /// its circumference matches the run's distance.
    static func loopTrack(distance: Double, duration: TimeInterval, seed: Int) -> [TrackPoint] {
        let centerLatitude = 51.5074 + Double(seed % 3) * 0.01
        let centerLongitude = -0.1657 - Double(seed % 4) * 0.008
        let radius = distance / (2 * .pi)
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = 111_320.0 * cos(centerLatitude * .pi / 180)
        let pointCount = max(2, Int(distance / 30))
        return (0...pointCount).map { index in
            let fraction = Double(index) / Double(pointCount)
            let angle = fraction * 2 * .pi
            let wobbled = radius * (1 + 0.18 * sin(angle * 3 + Double(seed)) + 0.08 * sin(angle * 7))
            return TrackPoint(
                latitude: centerLatitude + (wobbled * sin(angle)) / metersPerDegreeLatitude,
                longitude: centerLongitude + (wobbled * cos(angle)) / metersPerDegreeLongitude,
                elapsed: fraction * duration,
                distanceMeters: fraction * distance,
                energyKilocalories: fraction * distance * 0.065
            )
        }
    }
}
