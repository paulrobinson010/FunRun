import SwiftUI

/// Post-workout: the headline numbers, then the effort question. Saving
/// writes the score to HealthKit (as the workout's effort score) and sends
/// the run to the phone for history and shoe wear.
struct SummaryView: View {
    let workout: WorkoutManager

    @State private var effort = 5
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Workout done")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Time").foregroundStyle(.secondary)
                        Text(Format.duration(workout.elapsed))
                    }
                    GridRow {
                        Text("Distance").foregroundStyle(.secondary)
                        Text(Format.distance(workout.distanceMeters))
                    }
                    GridRow {
                        Text("Avg HR").foregroundStyle(.secondary)
                        Text("\(Format.heartRate(workout.averageHeartRate ?? workout.heartRate)) bpm")
                    }
                }
                .font(.footnote)

                if workout.savedWorkoutChunks.count > 1 {
                    Text("Saved as \(Self.chunkDescription(workout.savedWorkoutChunks))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text("How hard was that?")
                    .font(.headline)

                Picker("Effort", selection: $effort) {
                    ForEach(1...10, id: \.self) { score in
                        Text("\(score) · \(Self.effortLabel(score))").tag(score)
                    }
                }
                .frame(height: 56)

                Button {
                    save(effort: effort)
                } label: {
                    if saving {
                        ProgressView()
                    } else {
                        Label("Save", systemImage: "checkmark")
                            .font(.headline)
                    }
                }
                .tint(.green)
                .disabled(saving)

                Button("Skip effort") {
                    save(effort: nil)
                }
                .font(.footnote)
                .tint(.secondary)
                .disabled(saving)
            }
            .padding(.horizontal, 4)
        }
    }

    private func save(effort: Int?) {
        saving = true
        Task {
            await workout.finish(effort: effort)
            saving = false
        }
    }

    static func chunkDescription(_ chunks: [RunSegment]) -> String {
        chunks
            .map { "\($0.mode.label.lowercased()) \(Format.distance($0.distanceMeters))" }
            .joined(separator: " + ")
    }

    static func effortLabel(_ score: Int) -> String {
        switch score {
        case 1...2: "Easy"
        case 3...4: "Moderate"
        case 5...6: "Hard"
        case 7...8: "Very hard"
        default: "All out"
        }
    }
}
