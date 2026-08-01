import MapKit
import SwiftUI

struct RunDetailView: View {
    let run: RunSummary

    var body: some View {
        List {
            if let track = run.track, track.count >= 2 {
                Section {
                    RunMapView(track: track)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section {
                LabeledContent("Distance", value: Format.distance(run.distanceMeters))
                LabeledContent("Moving time", value: Format.duration(run.activeSeconds))
                LabeledContent("Avg pace", value: "\(Format.pace(run.averagePaceSecondsPerKm))/km")
                // A mixed outing gets each gait's own overall pace; a
                // pure walk or run is already the average above.
                if let runPace = run.averagePaceSecondsPerKm(in: .running),
                   let walkPace = run.averagePaceSecondsPerKm(in: .walking) {
                    LabeledContent("Run pace", value: "\(Format.pace(runPace))/km")
                    LabeledContent("Walk pace", value: "\(Format.pace(walkPace))/km")
                }
                LabeledContent("Avg heart rate", value: "\(Format.heartRate(run.averageHeartRate)) bpm")
                if let effort = run.effort {
                    LabeledContent(
                        run.walkEffort != nil ? "Run effort" : "Effort",
                        value: "\(effort)/10 · \(SummaryEffortLabel.text(effort))"
                    )
                }
                if let walkEffort = run.walkEffort {
                    LabeledContent("Walk effort", value: "\(walkEffort)/10 · \(SummaryEffortLabel.text(walkEffort))")
                }
                if let shoeName = run.shoeName {
                    LabeledContent("Shoes", value: shoeName)
                }
                if run.autoPauseCount > 0 {
                    LabeledContent("Auto-pauses", value: "\(run.autoPauseCount)")
                }
                // Tells a map that came up short apart from one that
                // never had the fixes to draw.
                if let accepted = run.gpsFixesAccepted {
                    LabeledContent(
                        "GPS fixes",
                        value: (run.gpsFixesRejected ?? 0) > 0
                            ? "\(accepted) · \(run.gpsFixesRejected ?? 0) too coarse"
                            : "\(accepted)"
                    )
                }
            }

            if let saved = run.savedWorkouts, saved.count > 1 {
                Section("Saved to Health as") {
                    ForEach(Array(saved.enumerated()), id: \.offset) { index, chunk in
                        LabeledContent {
                            Text(Format.distance(chunk.distanceMeters))
                        } label: {
                            Label("\(index + 1). \(chunk.mode.label)", systemImage: chunk.mode.symbolName)
                        }
                    }
                }
            }

            Section("Walk / run split") {
                LabeledContent {
                    Text(Format.distance(run.distance(in: .running)))
                } label: {
                    Label("Running", systemImage: ActivityMode.running.symbolName)
                }
                LabeledContent {
                    Text(Format.distance(run.distance(in: .walking)))
                } label: {
                    Label("Walking", systemImage: ActivityMode.walking.symbolName)
                }
            }

            if !run.segments.isEmpty {
                Section("Segments") {
                    ForEach(Array(run.segments.enumerated()), id: \.offset) { _, segment in
                        HStack {
                            Label(segment.mode.label, systemImage: segment.mode.symbolName)
                            Spacer()
                            Text(Format.distance(segment.distanceMeters))
                                .foregroundStyle(.secondary)
                            Text(segment.start, format: .dateTime.hour().minute())
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle(run.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The run's route drawn from the synced track, start and finish marked.
struct RunMapView: View {
    let track: [TrackPoint]

    private var coordinates: [CLLocationCoordinate2D] {
        track.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        Map(interactionModes: [.pan, .zoom]) {
            MapPolyline(coordinates: coordinates)
                .stroke(.blue, lineWidth: 3)
            if let start = coordinates.first {
                Annotation("Start", coordinate: start) {
                    Circle().fill(.green).frame(width: 10, height: 10)
                }
            }
            if let end = coordinates.last {
                Annotation("Finish", coordinate: end) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                }
            }
        }
    }
}

/// Same wording the watch uses when asking for the score.
enum SummaryEffortLabel {
    static func text(_ score: Int) -> String {
        switch score {
        case 1...2: "Easy"
        case 3...4: "Moderate"
        case 5...6: "Hard"
        case 7...8: "Very hard"
        default: "All out"
        }
    }
}
