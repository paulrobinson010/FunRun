import Foundation

enum Format {
    /// "5.21 km" (or "421 m" under a kilometre).
    static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.2f km", meters / 1000)
    }

    /// "5'32\"" per-kilometre pace from seconds/km; em dash when unknown.
    static func pace(_ secondsPerKm: Double?) -> String {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0, secondsPerKm < 3600 else {
            return "—'——\""
        }
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    /// "42:05" or "1:02:44".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// "+0:08" / "−0:12" — a delta against a reference time.
    static func signedDuration(_ seconds: TimeInterval) -> String {
        (seconds < 0 ? "−" : "+") + duration(abs(seconds))
    }

    static func heartRate(_ bpm: Double?) -> String {
        guard let bpm, bpm > 0 else { return "—" }
        return "\(Int(bpm.rounded()))"
    }
}
