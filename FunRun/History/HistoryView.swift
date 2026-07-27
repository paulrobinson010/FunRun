import SwiftUI

/// Runs synced from the watch, newest first.
struct HistoryView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            List {
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
            }
            .navigationTitle("History")
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
