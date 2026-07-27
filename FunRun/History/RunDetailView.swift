import SwiftUI

struct RunDetailView: View {
    let run: RunSummary

    var body: some View {
        List {
            Section {
                LabeledContent("Distance", value: Format.distance(run.distanceMeters))
                LabeledContent("Moving time", value: Format.duration(run.activeSeconds))
                LabeledContent("Avg pace", value: "\(Format.pace(run.averagePaceSecondsPerKm))/km")
                LabeledContent("Avg heart rate", value: "\(Format.heartRate(run.averageHeartRate)) bpm")
                if let effort = run.effort {
                    LabeledContent("Effort", value: "\(effort)/10 · \(SummaryEffortLabel.text(effort))")
                }
                if let shoeName = run.shoeName {
                    LabeledContent("Shoes", value: shoeName)
                }
                if run.autoPauseCount > 0 {
                    LabeledContent("Auto-pauses", value: "\(run.autoPauseCount)")
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
