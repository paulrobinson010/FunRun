import SwiftUI

/// Pick a pair of trainers (synced from the phone) and go. Runs without a
/// shoe are fine too — wear just isn't attributed anywhere.
struct StartView: View {
    let workout: WorkoutManager
    let sync: WatchSync

    @State private var selectedShoeID: UUID?

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

                Button {
                    let shoe = sync.activeShoes.first { $0.id == selectedShoeID }
                    Task {
                        workout.dismissFailure()
                        await workout.start(with: shoe)
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
}
