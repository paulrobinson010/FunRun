import Foundation

/// What the runner is doing right now, as detected automatically from
/// cadence and speed. A session freely mixes both; the split is recorded
/// as segments on the finished run.
enum ActivityMode: String, Codable, Hashable {
    case walking
    case running

    var label: String {
        switch self {
        case .walking: "Walking"
        case .running: "Running"
        }
    }

    var symbolName: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        }
    }
}
