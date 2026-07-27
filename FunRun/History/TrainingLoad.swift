import Foundation

/// Session-RPE training load: effort (1–10, default 5 when unrated) ×
/// moving minutes, summed per calendar week. The classic rule of thumb —
/// a week far above your recent average is where niggles come from — is
/// surfaced as a ramp warning.
enum TrainingLoad {
    /// This week's load is flagged when it exceeds the 4-week average by
    /// this factor.
    static let rampWarningFactor = 1.4

    struct WeekSummary {
        var distanceMeters: Double
        var load: Double
        /// This week ÷ the average of the previous four (nil until
        /// there's history to compare against).
        var rampRatio: Double?

        var isRamping: Bool {
            (rampRatio ?? 0) >= TrainingLoad.rampWarningFactor
        }
    }

    static func thisWeek(from runs: [RunSummary], now: Date = Date()) -> WeekSummary? {
        let calendar = Calendar.current
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }

        let currentRuns = runs.filter { $0.startDate >= thisWeekStart }
        let current = WeekSummary(
            distanceMeters: currentRuns.reduce(0) { $0 + $1.distanceMeters },
            load: load(of: currentRuns),
            rampRatio: nil
        )

        var previousLoads: [Double] = []
        for weeksBack in 1...4 {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: thisWeekStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }
            previousLoads.append(load(of: runs.filter { $0.startDate >= start && $0.startDate < end }))
        }
        let baseline = previousLoads.reduce(0, +) / Double(max(1, previousLoads.count))

        var summary = current
        if baseline > 0 {
            summary.rampRatio = current.load / baseline
        }
        return summary
    }

    private static func load(of runs: [RunSummary]) -> Double {
        runs.reduce(0) { $0 + Double($1.effort ?? 5) * ($1.activeSeconds / 60) }
    }
}
