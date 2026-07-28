import CoreMotion
import Foundation
import HealthKit
import Observation
import WatchKit

/// A completed kilometre: its moving time and how it compared to the one
/// before.
struct KmSplit: Equatable {
    var kilometre: Int
    var seconds: TimeInterval
    var deltaToPrevious: TimeInterval?
    var at: Date
}

/// Runs the whole session on the watch: the HealthKit workout (live heart
/// rate, GPS-calibrated distance), walk/run auto-detection, and auto-pause.
///
/// HealthKit cannot change a workout's activity type mid-session, so the
/// workout is saved as an outdoor run and the walk/run split lives in the
/// segments on `RunSummary`.
@MainActor
@Observable
final class WorkoutManager: NSObject {
    enum Phase: Equatable {
        case idle
        case starting
        case active
        case paused(auto: Bool)
        /// Session over, waiting on the effort score.
        case ended
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var mode: ActivityMode = .walking
    private(set) var elapsed: TimeInterval = 0
    private(set) var distanceMeters: Double = 0
    private(set) var heartRate: Double = 0
    private(set) var speedMetersPerSecond: Double = 0
    private(set) var shoe: Shoe?
    /// Set once collection ends; what the summary screen shows as avg HR.
    private(set) var averageHeartRate: Double?
    /// The walk/run blocks the session was saved to HealthKit as — one
    /// workout each. A single entry means the whole session fell back to
    /// one workout (e.g. the running never passed the gate).
    private(set) var savedWorkoutChunks: [RunSegment] = []
    private(set) var activeEnergyKilocalories: Double = 0
    /// Non-nil while standing at a known intersection: what each choice
    /// is expected to cost, from past runs through this exact spot.
    private(set) var routePrediction: RoutePrediction?
    /// How the segment just completed compares to the last 28 days of
    /// the same stretch. Shown briefly, then auto-hidden.
    private(set) var segmentComparison: SegmentComparison?
    /// Live standing against the ghost, when this session races one.
    private(set) var ghostStatus: GhostStatus?
    /// The kilometre split that just completed — a wrist tap plus a brief
    /// banner with its moving time and delta to the previous kilometre.
    private(set) var kmSplit: KmSplit?

    /// Past routes offered as ghosts on the start screen — the last 12
    /// months, newest first.
    var ghostCandidates: [RouteMeta] {
        routeStore.metas
    }

    /// Load a ghost's full track for the picker's selection.
    func ghostRoute(withID id: UUID) -> RouteRun? {
        routeStore.run(withID: id)
    }

    /// Name (or rename) a favourite route; nil removes the favourite.
    func setFavourite(routeID: UUID, name: String?) {
        routeStore.setFavourite(routeID, name: name)
    }

    /// Called with the finished summary once the effort score is in.
    var onFinished: ((RunSummary) -> Void)?

    /// Current pace in seconds per km, from the smoothed live speed.
    var currentPaceSecondsPerKm: Double? {
        guard speedMetersPerSecond > 0.3 else { return nil }
        return 1000 / speedMetersPerSecond
    }

    var isAutoPaused: Bool { phase == .paused(auto: true) }

    // Stationary below this speed; 5 s of it triggers auto-pause.
    private let stopSpeed: Double = 0.6
    private let autoPauseAfter: TimeInterval = 5
    private let resumeSpeed: Double = 0.9

    private let healthStore = HKHealthStore()
    private let pedometer = CMPedometer()
    private let routeRecorder = RouteRecorder()
    private let routeStore = RouteHistoryStore()
    private var routePredictor: RoutePredictor?
    private var ghostTracker: GhostTracker?
    /// The last decision point passed, and the wall-clock offset when it
    /// was — start of the segment currently being run.
    private var lastDecisionPassage: (key: RouteGraph.GridKey, wallElapsed: TimeInterval)?
    private let comparisonDisplaySeconds: TimeInterval = 25

    // Kilometre split bookkeeping (moving time, from builder elapsed).
    private var nextSplitMeters: Double = 1000
    private var lastSplitElapsed: TimeInterval = 0
    private var previousSplitSeconds: TimeInterval?
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var classifier = ActivityClassifier()
    private var tickTask: Task<Void, Never>?

    // Pedometer feed — keeps updating even while the HK session is paused,
    // which is what lets auto-pause detect movement and resume.
    private var cadence: Double?
    private var pedometerSpeed: Double?
    private var pedometerUpdatedAt = Date.distantPast
    private var pedometerStartDistance: Double = 0

    // Distance history for a speed estimate when the pedometer is quiet.
    private var distanceHistory: [(date: Date, meters: Double)] = []

    private var lastMovementAt = Date()
    private var pendingAutoPause = false
    private var autoPauseCount = 0
    /// Auto-pause only arms once movement has actually been seen: at the
    /// start GPS and the pedometer take several seconds to warm up, and
    /// without this the session pauses on the doorstep before the first
    /// step registers.
    private var hasDetectedMovement = false

    private var segments: [RunSegment] = []
    private var segmentStart: Date?
    private var segmentStartDistance: Double = 0

    private var startDate = Date()
    private var endDate = Date()
    /// The workouts actually written to HealthKit — one per saved chunk,
    /// or one for the whole session. The effort score is related to each.
    private var finishedWorkouts: [HKWorkout] = []

    // Raw material for splitting the session into per-chunk workouts:
    // our own copy of the heart-rate stream, and every pause interval.
    private var heartRateHistory: [(date: Date, bpm: Double)] = []
    private var pauseIntervals: [DateInterval] = []
    private var currentPauseStart: Date?

    // MARK: - Lifecycle

    func start(with shoe: Shoe?, ghost: RouteRun? = nil) async {
        guard phase == .idle || isFailed else { return }
        phase = .starting
        self.shoe = shoe
        ghostTracker = ghost.map { GhostTracker(route: $0) }
        ghostStatus = nil
        do {
            try await requestAuthorization()

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .running
            configuration.locationType = .outdoor

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let start = Date()
            startDate = start
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)

            let storedPace = UserDefaults.standard.double(forKey: ActivityClassifier.runPaceKey)
            classifier = ActivityClassifier(
                runPaceKmh: storedPace > 0 ? storedPace : ActivityClassifier.defaultRunPaceKmh
            )
            mode = .walking
            segments = []
            beginSegment(at: start)
            autoPauseCount = 0
            hasDetectedMovement = false
            lastMovementAt = start
            distanceMeters = 0
            heartRate = 0
            elapsed = 0
            distanceHistory = []
            heartRateHistory = []
            pauseIntervals = []
            currentPauseStart = nil
            savedWorkoutChunks = []
            finishedWorkouts = []

            activeEnergyKilocalories = 0
            routePrediction = nil
            segmentComparison = nil
            lastDecisionPassage = nil
            kmSplit = nil
            nextSplitMeters = 1000
            lastSplitElapsed = 0
            previousSplitSeconds = nil
            // A year of tracks is too much to crunch on the main actor;
            // predictions simply stay off until the graph is ready
            // (they need a GPS fix first anyway). The same pass upgrades
            // a favourite ghost to the fastest recorded attempt of that
            // route — a favourite means the route, not one day's run.
            routePredictor = nil
            let favouriteGhost = ghost.flatMap { candidate in
                routeStore.metas.first { $0.id == candidate.id }?.isFavourite == true ? candidate : nil
            }
            Task.detached(priority: .utility) { [weak self] in
                let runs = RouteHistoryStore.loadAllRuns()
                let predictor = RoutePredictor(runs: runs)
                let bestAttempt = favouriteGhost.map { RouteMatcher.fastestMatch(for: $0, in: runs) }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.routePredictor = predictor
                    if let bestAttempt, bestAttempt.id != favouriteGhost?.id, self.ghostTracker != nil {
                        self.ghostTracker = GhostTracker(route: bestAttempt)
                        self.ghostStatus = nil
                    }
                }
            }
            routeRecorder.metrics = { [weak self] in
                (self?.distanceMeters ?? 0, self?.activeEnergyKilocalories ?? 0)
            }
            routeRecorder.start(at: start)

            startPedometer(from: start)
            startTicking()
            phase = .active
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Called from the start screen so the location grant happens calmly
    /// in the foreground, not in the middle of starting a workout.
    func requestLocationPermission() {
        routeRecorder.requestPermissionIfNeeded()
    }

    func togglePause() {
        switch phase {
        case .active:
            pendingAutoPause = false
            session?.pause()
        case .paused:
            session?.resume()
        default:
            break
        }
    }

    func end() {
        guard phase == .active || phase.isPaused else { return }
        session?.end()
    }

    /// Save the perceived-effort score (nil = skipped), hand the summary
    /// off, and go back to idle.
    func finish(effort: Int?) async {
        guard phase == .ended else { return }
        if let effort {
            await saveEffortToHealthKit(effort)
        }
        let summary = RunSummary(
            startDate: startDate,
            endDate: endDate,
            activeSeconds: elapsed,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            effort: effort,
            shoeID: shoe?.id,
            shoeName: shoe?.displayName,
            segments: segments,
            autoPauseCount: autoPauseCount,
            savedWorkouts: savedWorkoutChunks,
            track: mapTrack()
        )
        onFinished?(summary)
        reset()
    }

    func dismissFailure() {
        if isFailed { phase = .idle }
    }

    // MARK: - Authorization

    private func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "FunRun", code: 1, userInfo: [NSLocalizedDescriptionKey: "Health data is not available."])
        }
        var share: Set<HKSampleType> = [
            HKQuantityType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
        ]
        var read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.runningSpeed),
        ]
        if #available(watchOS 11.0, *) {
            share.insert(HKQuantityType(.workoutEffortScore))
            read.insert(HKQuantityType(.workoutEffortScore))
        }
        try await healthStore.requestAuthorization(toShare: share, read: read)
    }

    // MARK: - Pedometer

    private func startPedometer(from start: Date) {
        cadence = nil
        pedometerSpeed = nil
        pedometerUpdatedAt = .distantPast
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: start) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor in
                self?.ingest(data)
            }
        }
    }

    private func ingest(_ data: CMPedometerData) {
        pedometerUpdatedAt = Date()
        cadence = data.currentCadence.map { $0.doubleValue * 60 }
        if let pace = data.currentPace?.doubleValue, pace > 0 {
            pedometerSpeed = 1.0 / pace
        } else {
            pedometerSpeed = nil
        }
    }

    private func stopPedometer() {
        pedometer.stopUpdates()
    }

    // MARK: - The once-a-second tick

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard let builder else { return }
        let now = Date()
        elapsed = builder.elapsedTime

        let speed = currentSpeed(at: now)
        speedMetersPerSecond = speed
        if speed > stopSpeed {
            lastMovementAt = now
            hasDetectedMovement = true
        }

        switch phase {
        case .active:
            if hasDetectedMovement, now.timeIntervalSince(lastMovementAt) >= autoPauseAfter {
                pendingAutoPause = true
                autoPauseCount += 1
                session?.pause()
            } else {
                let freshCadence = now.timeIntervalSince(pedometerUpdatedAt) < 3 ? cadence : nil
                let detected = classifier.update(cadence: freshCadence, speed: speed, at: now)
                if detected != mode {
                    closeSegment(at: now)
                    mode = detected
                    beginSegment(at: now)
                }
            }
            updateRoutePrediction()
            updateKmSplit()
        case .paused(auto: true):
            if speed >= resumeSpeed {
                session?.resume()
            }
        default:
            break
        }

        // Ghost guidance keeps working while paused — standing at a
        // corner working out where to go is exactly when it's needed.
        if phase == .active || phase.isPaused {
            updateGhostStatus()
        }
    }

    /// Crossing a kilometre boundary taps the wrist and flashes the
    /// split's moving time with its delta to the previous kilometre.
    private func updateKmSplit() {
        if distanceMeters >= nextSplitMeters {
            let seconds = elapsed - lastSplitElapsed
            kmSplit = KmSplit(
                kilometre: Int((nextSplitMeters / 1000).rounded()),
                seconds: seconds,
                deltaToPrevious: previousSplitSeconds.map { seconds - $0 },
                at: Date()
            )
            previousSplitSeconds = seconds
            lastSplitElapsed = elapsed
            nextSplitMeters += 1000
            WKInterfaceDevice.current().play(.notification)
        }
        if let split = kmSplit, Date().timeIntervalSince(split.at) > 20 {
            kmSplit = nil
        }
    }

    private func updateGhostStatus() {
        guard let tracker = ghostTracker, let location = routeRecorder.lastLocation else { return }
        let wallElapsed = Date().timeIntervalSince(startDate)
        let fresh = tracker.update(location: location, course: routeRecorder.course, wallElapsed: wallElapsed)
        if let fresh, let previous = ghostStatus, fresh.state != previous.state {
            switch fresh.state {
            case .offRoute: WKInterfaceDevice.current().play(.failure)
            case .onRoute: WKInterfaceDevice.current().play(.success)
            case .finished: WKInterfaceDevice.current().play(.success)
            }
        }
        ghostStatus = fresh ?? ghostStatus
    }

    /// Look up the current spot in the route graph. A haptic tap announces
    /// arrival at a new intersection so the wrist doesn't need watching.
    private func updateRoutePrediction() {
        guard let predictor = routePredictor,
              let location = routeRecorder.lastLocation,
              let course = routeRecorder.course else {
            routePrediction = nil
            return
        }
        let wallElapsed = Date().timeIntervalSince(startDate)
        let currentAverageSpeed = (wallElapsed > 180 && distanceMeters > 400) ? distanceMeters / wallElapsed : nil
        let fresh = predictor.prediction(
            at: location,
            course: course,
            energySoFar: activeEnergyKilocalories,
            currentAverageSpeed: currentAverageSpeed
        )
        if let fresh, fresh.nodeKey != routePrediction?.nodeKey {
            WKInterfaceDevice.current().play(.directionUp)
            recordDecisionPassage(at: fresh.nodeKey, predictor: predictor)
        }
        routePrediction = fresh

        if let comparison = segmentComparison,
           Date().timeIntervalSince(comparison.at) > comparisonDisplaySeconds {
            segmentComparison = nil
        }
    }

    /// Arriving at a fork closes the segment begun at the previous one:
    /// compare it against the recent history of the same stretch, then
    /// start timing the next segment from here.
    private func recordDecisionPassage(at key: RouteGraph.GridKey, predictor: RoutePredictor) {
        let wallElapsed = Date().timeIntervalSince(startDate)
        defer { lastDecisionPassage = (key, wallElapsed) }
        guard let previous = lastDecisionPassage, previous.key != key else { return }
        let seconds = wallElapsed - previous.wallElapsed
        guard seconds >= SegmentIndex.minimumSegmentSeconds else { return }
        segmentComparison = predictor.segmentComparison(from: previous.key, to: key, seconds: seconds)
    }

    /// Live speed: the pedometer's pace when fresh, otherwise the slope of
    /// recent HealthKit distance. Both go quiet when standing still, which
    /// correctly reads as zero.
    private func currentSpeed(at now: Date) -> Double {
        if now.timeIntervalSince(pedometerUpdatedAt) < 3, let pedometerSpeed {
            return pedometerSpeed
        }
        distanceHistory.removeAll { now.timeIntervalSince($0.date) > 10 }
        guard let oldest = distanceHistory.first,
              now.timeIntervalSince(oldest.date) >= 2 else { return 0 }
        return max(0, (distanceMeters - oldest.meters) / now.timeIntervalSince(oldest.date))
    }

    // MARK: - Segments

    private func beginSegment(at date: Date) {
        segmentStart = date
        segmentStartDistance = distanceMeters
    }

    private func closeSegment(at date: Date) {
        guard let start = segmentStart else { return }
        segments.append(RunSegment(
            mode: mode,
            start: start,
            end: date,
            distanceMeters: max(0, distanceMeters - segmentStartDistance)
        ))
        segmentStart = nil
    }

    // MARK: - Finishing

    private func finishCollection(at date: Date) async {
        stopPedometer()
        routeRecorder.stop()
        routePrediction = nil
        ghostStatus = nil
        tickTask?.cancel()
        tickTask = nil
        endDate = date
        saveRouteRun(endingAt: date)
        closeSegment(at: date)
        if let pauseStart = currentPauseStart {
            pauseIntervals.append(DateInterval(start: pauseStart, end: date))
            currentPauseStart = nil
        }
        guard let builder else {
            phase = .ended
            return
        }
        elapsed = builder.elapsedTime
        let bpm = HKUnit.count().unitDivided(by: .minute())
        averageHeartRate = builder.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?.doubleValue(for: bpm)
        let totalEnergy = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())

        let chunks = WorkoutChunker.chunks(from: segments)
        do {
            try await builder.endCollection(at: date)
            // A pure running session keeps the live workout — it carries
            // the richest data. Anything else (a chain, or an
            // all-walking session started as .running) is rebuilt as one
            // correctly-typed workout per chunk.
            if chunks.count <= 1, (chunks.first?.mode ?? .running) == .running {
                if let workout = try await builder.finishWorkout() {
                    finishedWorkouts = [workout]
                }
                savedWorkoutChunks = chunks.isEmpty
                    ? [RunSegment(mode: .running, start: startDate, end: date, distanceMeters: distanceMeters)]
                    : chunks
            } else {
                await saveChunkedWorkouts(chunks, totalEnergy: totalEnergy, liveBuilder: builder)
            }
        } catch {
            finishedWorkouts = []
            savedWorkoutChunks = chunks
        }
        await attachWorkoutRoutes()
        phase = .ended
    }

    /// Attach the GPS track to each saved workout so the Fitness app can
    /// draw its map — each chunk workout gets its slice of the route.
    private func attachWorkoutRoutes() async {
        let locations = routeRecorder.rawLocations
        guard !locations.isEmpty else { return }
        for workout in finishedWorkouts {
            let slice = locations.filter {
                $0.timestamp >= workout.startDate && $0.timestamp <= workout.endDate
            }
            guard slice.count >= 2 else { continue }
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
            do {
                try await routeBuilder.insertRouteData(slice)
                _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
            } catch {
                // A workout without a map is still a workout.
            }
        }
    }

    /// Write one HealthKit workout per chunk, typed walking or running,
    /// carrying that chunk's distance, its slice of the heart-rate stream,
    /// a distance-proportional share of the energy, and any pauses that
    /// fell inside it. Only once every chunk has saved is the live
    /// workout discarded — if anything fails, the partial saves are
    /// rolled back and the whole session is kept as the single live
    /// workout instead, so a run is never lost.
    private func saveChunkedWorkouts(_ chunks: [RunSegment], totalEnergy: Double?, liveBuilder: HKLiveWorkoutBuilder) async {
        var saved: [HKWorkout] = []
        do {
            for chunk in chunks {
                saved.append(try await saveWorkout(for: chunk, totalEnergy: totalEnergy))
            }
            liveBuilder.discardWorkout()
            finishedWorkouts = saved
            savedWorkoutChunks = chunks
        } catch {
            for workout in saved {
                try? await healthStore.delete(workout)
            }
            do {
                if let workout = try await liveBuilder.finishWorkout() {
                    finishedWorkouts = [workout]
                } else {
                    finishedWorkouts = []
                }
                savedWorkoutChunks = [RunSegment(mode: .running, start: startDate, end: endDate, distanceMeters: distanceMeters)]
            } catch {
                finishedWorkouts = []
                savedWorkoutChunks = chunks
            }
        }
    }

    /// The recorded track thinned to ~20 m spacing — light enough to ride
    /// along on the phone sync, detailed enough to draw the run's map.
    private func mapTrack() -> [TrackPoint]? {
        let points = routeRecorder.points
        guard points.count >= 2 else { return nil }
        var thinned: [TrackPoint] = []
        var lastKeptDistance = -Double.greatestFiniteMagnitude
        for point in points where point.distanceMeters - lastKeptDistance >= 20 {
            thinned.append(point)
            lastKeptDistance = point.distanceMeters
        }
        if let last = points.last, thinned.last?.distanceMeters != last.distanceMeters {
            thinned.append(last)
        }
        return thinned
    }

    /// Keep this session's GPS track as prediction history — but only a
    /// real outing; a doorstep false start would just add noise.
    private func saveRouteRun(endingAt date: Date) {
        let points = routeRecorder.points
        guard distanceMeters >= 500, points.count >= 20 else { return }
        routeStore.add(RouteRun(
            date: startDate,
            totalSeconds: date.timeIntervalSince(startDate),
            totalEnergyKilocalories: activeEnergyKilocalories,
            points: points
        ))
    }

    private func saveWorkout(for chunk: RunSegment, totalEnergy: Double?) async throws -> HKWorkout {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = chunk.mode == .running ? .running : .walking
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        try await builder.beginCollection(at: chunk.start)

        var samples: [HKSample] = []
        if chunk.distanceMeters > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.distanceWalkingRunning),
                quantity: HKQuantity(unit: .meter(), doubleValue: chunk.distanceMeters),
                start: chunk.start,
                end: chunk.end
            ))
        }
        if let totalEnergy, totalEnergy > 0, distanceMeters > 0 {
            let share = totalEnergy * (chunk.distanceMeters / distanceMeters)
            if share > 0 {
                samples.append(HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: share),
                    start: chunk.start,
                    end: chunk.end
                ))
            }
        }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        for reading in heartRateHistory where reading.date >= chunk.start && reading.date <= chunk.end {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: bpm, doubleValue: reading.bpm),
                start: reading.date,
                end: reading.date
            ))
        }
        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }

        var events: [HKWorkoutEvent] = []
        for pause in pauseIntervals where pause.start >= chunk.start && pause.end <= chunk.end {
            events.append(HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pause.start, duration: 0), metadata: nil))
            events.append(HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: pause.end, duration: 0), metadata: nil))
        }
        if !events.isEmpty {
            try await builder.addWorkoutEvents(events)
        }

        try await builder.endCollection(at: chunk.end)
        guard let workout = try await builder.finishWorkout() else {
            throw NSError(domain: "FunRun", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "HealthKit did not return the finished workout.",
            ])
        }
        return workout
    }

    private func saveEffortToHealthKit(_ effort: Int) async {
        guard #available(watchOS 11.0, *) else { return }
        // One score for the outing, related to every workout it produced.
        for workout in finishedWorkouts {
            let sample = HKQuantitySample(
                type: HKQuantityType(.workoutEffortScore),
                quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: Double(effort)),
                start: workout.startDate,
                end: workout.endDate
            )
            do {
                try await healthStore.save(sample)
                _ = try await healthStore.relateWorkoutEffortSample(sample, with: workout, activity: nil)
            } catch {
                // The score still travels on the RunSummary even if
                // HealthKit declines the related sample.
            }
        }
    }

    private func reset() {
        session = nil
        builder = nil
        finishedWorkouts = []
        savedWorkoutChunks = []
        heartRateHistory = []
        pauseIntervals = []
        currentPauseStart = nil
        averageHeartRate = nil
        routePredictor = nil
        routePrediction = nil
        segmentComparison = nil
        lastDecisionPassage = nil
        ghostTracker = nil
        ghostStatus = nil
        kmSplit = nil
        activeEnergyKilocalories = 0
        shoe = nil
        segments = []
        segmentStart = nil
        distanceHistory = []
        phase = .idle
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
}

extension WorkoutManager.Phase {
    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.lastMovementAt = date
                if let pauseStart = self.currentPauseStart {
                    self.pauseIntervals.append(DateInterval(start: pauseStart, end: date))
                    self.currentPauseStart = nil
                }
                self.phase = .active
            case .paused:
                self.currentPauseStart = date
                self.phase = .paused(auto: self.pendingAutoPause)
                self.pendingAutoPause = false
            case .ended:
                await self.finishCollection(at: date)
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heartRate = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?.doubleValue(for: bpm)
        let distance = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter())
        let energy = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in
            if let heartRate {
                self.heartRate = heartRate
                self.heartRateHistory.append((Date(), heartRate))
            }
            if let distance {
                self.distanceMeters = distance
                self.distanceHistory.append((Date(), distance))
            }
            if let energy {
                self.activeEnergyKilocalories = energy
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
