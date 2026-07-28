import SwiftUI

/// Runs synced from the watch, newest first.
struct HistoryView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let week = TrainingLoad.thisWeek(from: model.runLog.runs), week.load > 0 {
                    Section("This week") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(Format.distance(week.distanceMeters), systemImage: "figure.run")
                                Spacer()
                                Text("Load \(Int(week.load.rounded()))")
                                    .foregroundStyle(.secondary)
                            }
                            if let ratio = week.rampRatio {
                                let percent = Int(((ratio - 1) * 100).rounded())
                                Text("\(percent >= 0 ? "+" : "")\(percent)% vs 4-week average\(week.isRamping ? " — easy does it" : "")")
                                    .font(.caption)
                                    .foregroundStyle(week.isRamping ? .orange : .secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if model.runLog.runs.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "figure.run",
                        description: Text("Finish a workout on your watch and it appears here.")
                    )
                }
                ForEach(model.runLog.runs) { run in
                    NavigationLink {
                        RunDetailView(run: run)
                    } label: {
                        RunRow(run: run)
                    }
                }
                .onDelete { offsets in
                    for run in offsets.map({ model.runLog.runs[$0] }) {
                        model.delete(run)
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !model.runLog.runs.isEmpty {
                    EditButton()
                }
            }
        }
    }
}

struct RunRow: View {
    let run: RunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(run.startDate, format: .dateTime.weekday(.abbreviated).day().month())
                    .font(.headline)
                Spacer()
                if let effort = run.effort {
                    Text("Effort \(effort)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
            }
            HStack(spacing: 12) {
                Label(Format.distance(run.distanceMeters), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Label(Format.duration(run.activeSeconds), systemImage: "stopwatch")
                Label("\(Format.pace(run.averagePaceSecondsPerKm))/km", systemImage: "speedometer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
