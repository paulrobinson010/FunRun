import Foundation

/// Decides walking vs running from cadence and speed. Cadence is the
/// strongest signal — running is a gait change, not just a speed change —
/// with speed as the fallback when the pedometer has nothing fresh.
///
/// A switch only happens after the new gait is sustained for a few
/// seconds, so a couple of quick steps across a road or a short stumble
/// doesn't flip the mode back and forth.
struct ActivityClassifier {
    /// What counts as a run is personal — this is the user's setting,
    /// asked for on the watch (default 9 km/h ≈ 6'40"/km).
    static let defaultRunPaceKmh: Double = 9
    static let runPaceKey = "runPaceKmh"

    private(set) var mode: ActivityMode = .walking

    private var candidate: ActivityMode?
    private var candidateSince: Date?

    /// Seconds the new gait must hold before the mode switches.
    private let sustainSeconds: TimeInterval = 6

    /// Steps per minute above which the gait reads as running, and at or
    /// below which it reads as walking. The gap between them is a dead
    /// zone that keeps the current mode.
    private let runningCadence: Double = 140
    private let walkingCadence: Double = 128

    /// Speed thresholds (m/s) used only when cadence is unavailable —
    /// derived from the user's run pace, with a hysteresis band below.
    private let runningSpeed: Double
    private let walkingSpeed: Double

    init(runPaceKmh: Double = ActivityClassifier.defaultRunPaceKmh) {
        let clamped = min(20, max(4, runPaceKmh))
        runningSpeed = clamped / 3.6
        walkingSpeed = runningSpeed * 0.85
    }

    mutating func update(cadence: Double?, speed: Double, at now: Date) -> ActivityMode {
        let suggested: ActivityMode
        if let cadence, cadence > 0 {
            if cadence >= runningCadence {
                suggested = .running
            } else if cadence <= walkingCadence {
                suggested = .walking
            } else {
                suggested = mode
            }
        } else if speed >= runningSpeed {
            suggested = .running
        } else if speed < walkingSpeed {
            suggested = .walking
        } else {
            suggested = mode
        }

        guard suggested != mode else {
            candidate = nil
            candidateSince = nil
            return mode
        }
        if candidate == suggested, let since = candidateSince {
            if now.timeIntervalSince(since) >= sustainSeconds {
                mode = suggested
                candidate = nil
                candidateSince = nil
            }
        } else {
            candidate = suggested
            candidateSince = now
        }
        return mode
    }

    mutating func reset(to startMode: ActivityMode = .walking) {
        mode = startMode
        candidate = nil
        candidateSince = nil
    }
}
