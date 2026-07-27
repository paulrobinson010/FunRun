import CoreMotion
import Foundation
import HealthKit
import Observation

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

    private var segments: [RunSegment] = []
    private var segmentStart: Date?
    private var segmentStartDistance: Double = 0

    private var startDate = Date()
    private var endDate = Date()
    private var finishedWorkout: HKWorkout?

    // MARK: - Lifecycle

    func start(with shoe: Shoe?) async {
        guard phase == .idle || isFailed else { return }
        phase = .starting
        self.shoe = shoe
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

            classifier.reset()
            mode = .walking
            segments = []
            beginSegment(at: start)
            autoPauseCount = 0
            lastMovementAt = start
            distanceMeters = 0
            heartRate = 0
            elapsed = 0
            distanceHistory = []

            startPedometer(from: start)
            startTicking()
            phase = .active
        } catch {
            phase = .failed(error.localizedDescription)
        }
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
            autoPauseCount: autoPauseCount
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
        }

        switch phase {
        case .active:
            if now.timeIntervalSince(lastMovementAt) >= autoPauseAfter {
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
        case .paused(auto: true):
            if speed >= resumeSpeed {
                session?.resume()
            }
        default:
            break
        }
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
        tickTask?.cancel()
        tickTask = nil
        endDate = date
        closeSegment(at: date)
        guard let builder else {
            phase = .ended
            return
        }
        elapsed = builder.elapsedTime
        let bpm = HKUnit.count().unitDivided(by: .minute())
        averageHeartRate = builder.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?.doubleValue(for: bpm)
        do {
            try await builder.endCollection(at: date)
            finishedWorkout = try await builder.finishWorkout()
        } catch {
            finishedWorkout = nil
        }
        phase = .ended
    }

    private func saveEffortToHealthKit(_ effort: Int) async {
        guard #available(watchOS 11.0, *), let workout = finishedWorkout else { return }
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
            // The score still travels on the RunSummary even if HealthKit
            // declines the related sample.
        }
    }

    private func reset() {
        session = nil
        builder = nil
        finishedWorkout = nil
        averageHeartRate = nil
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
                self.phase = .active
            case .paused:
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
        Task { @MainActor in
            if let heartRate {
                self.heartRate = heartRate
            }
            if let distance {
                self.distanceMeters = distance
                self.distanceHistory.append((Date(), distance))
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
