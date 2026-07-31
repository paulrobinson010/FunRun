import SwiftUI

/// Post-workout: the headline numbers, then the effort question — asked
/// per mode (walking and running separately when the outing had both),
/// defaulting to what you answered last time. Saving writes each score to
/// its HealthKit workout and sends the run to the phone for history and
/// shoe wear.
struct SummaryView: View {
    let workout: WorkoutManager

    @AppStorage("lastRunEffort") private var lastRunEffort = 5
    @AppStorage("lastWalkEffort") private var lastWalkEffort = 3
    @State private var runEffort = 5
    @State private var walkEffort = 3
    @State private var saving = false

    /// Which modes actually got saved as workouts — decides which effort
    /// questions to ask.
    private var asksRunning: Bool {
        // Empty chunks shouldn't happen, but if it does, still ask
        // something rather than showing a Save button with no question.
        workout.savedWorkoutChunks.isEmpty
            || workout.savedWorkoutChunks.contains { $0.mode == .running }
    }

    private var asksWalking: Bool {
        workout.savedWorkoutChunks.contains { $0.mode == .walking }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Workout done")
                    .font(.headline)
                    .foregroundStyle(Gaitway.gradient)

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

                if asksRunning {
                    if asksWalking {
                        Label("Run", systemImage: ActivityMode.running.symbolName)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Gaitway.magenta)
                    }
                    effortPicker("Run effort", selection: $runEffort)
                }
                if asksWalking {
                    if asksRunning {
                        Label("Walk", systemImage: ActivityMode.walking.symbolName)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Gaitway.cyan)
                    }
                    effortPicker("Walk effort", selection: $walkEffort)
                }

                Button {
                    save(skipped: false)
                } label: {
                    if saving {
                        ProgressView()
                    } else {
                        Label("Save", systemImage: "checkmark")
                            .font(.headline)
                    }
                }
                .tint(Gaitway.cyan)
                .disabled(saving)

                Button("Skip effort") {
                    save(skipped: true)
                }
                .font(.footnote)
                .tint(.secondary)
                .disabled(saving)
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            runEffort = lastRunEffort
            walkEffort = lastWalkEffort
        }
    }

    private func effortPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(1...10, id: \.self) { score in
                Text("\(score) · \(Self.effortLabel(score))").tag(score)
            }
        }
        .labelsHidden()
        .frame(height: 52)
    }

    private func save(skipped: Bool) {
        let run = (!skipped && asksRunning) ? runEffort : nil
        let walk = (!skipped && asksWalking) ? walkEffort : nil
        if let run { lastRunEffort = run }
        if let walk { lastWalkEffort = walk }
        saving = true
        Task {
            await workout.finish(runEffort: run, walkEffort: walk)
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
