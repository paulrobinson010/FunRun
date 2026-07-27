import SwiftUI

/// Pick a pair of trainers (synced from the phone) and go. Runs without a
/// shoe are fine too — wear just isn't attributed anywhere.
struct StartView: View {
    let workout: WorkoutManager
    let sync: WatchSync

    @State private var selectedShoeID: UUID?
    @State private var selectedGhostID: UUID?

    var body: some View {
        NavigationStack {
            startContent
        }
    }

    private var startContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.title2)
                    .foregroundStyle(.green)

                if case .failed(let message) = workout.phase {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if !sync.activeShoes.isEmpty {
                    Picker("Trainers", selection: $selectedShoeID) {
                        Text("No shoes").tag(UUID?.none)
                        ForEach(sync.activeShoes) { shoe in
                            Text(shoe.displayName).tag(UUID?.some(shoe.id))
                        }
                    }
                    .frame(height: 48)
                }

                if !workout.ghostCandidates.isEmpty {
                    NavigationLink {
                        GhostPickerView(candidates: workout.ghostCandidates, selectedID: $selectedGhostID)
                    } label: {
                        HStack {
                            Image(systemName: "figure.run.circle")
                                .foregroundStyle(.purple)
                            Text(selectedGhostLabel)
                                .lineLimit(1)
                        }
                        .font(.footnote)
                    }
                }

                Button {
                    let shoe = sync.activeShoes.first { $0.id == selectedShoeID }
                    let ghost = selectedGhostID.flatMap { workout.ghostRoute(withID: $0) }
                    Task {
                        workout.dismissFailure()
                        await workout.start(with: shoe, ghost: ghost)
                    }
                } label: {
                    if workout.phase == .starting {
                        ProgressView()
                    } else {
                        Label("Start", systemImage: "play.fill")
                            .font(.headline)
                    }
                }
                .tint(.green)
                .disabled(workout.phase == .starting)

                Text("Walk or run — it works out which. Stops auto-pause after 5 seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("FunRun")
        .onAppear {
            if selectedShoeID == nil {
                selectedShoeID = sync.activeShoes.first?.id
            }
        }
    }

    private var selectedGhostLabel: String {
        guard let meta = workout.ghostCandidates.first(where: { $0.id == selectedGhostID }) else {
            return "No ghost"
        }
        return meta.ghostLabel
    }
}

/// The last 12 months of routes, newest first — pick one to race.
struct GhostPickerView: View {
    let candidates: [RouteMeta]
    @Binding var selectedID: UUID?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Button {
                selectedID = nil
                dismiss()
            } label: {
                HStack {
                    Text("No ghost")
                    Spacer()
                    if selectedID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            ForEach(candidates) { meta in
                Button {
                    selectedID = meta.id
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(meta.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                            Spacer()
                            if selectedID == meta.id {
                                Image(systemName: "checkmark")
                            }
                        }
                        Text("\(Format.distance(meta.totalDistanceMeters)) · \(Format.duration(meta.totalSeconds))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Ghost")
    }
}

extension RouteMeta {
    /// "22 Jul 25 · 7.51 km" — enough to recognise a route by.
    var ghostLabel: String {
        let day = date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
        return "\(day) · \(Format.distance(totalDistanceMeters))"
    }
}
