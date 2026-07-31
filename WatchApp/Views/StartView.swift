import SwiftUI

/// Pick a pair of trainers (synced from the phone) and go. Runs without a
/// shoe are fine too — wear just isn't attributed anywhere.
struct StartView: View {
    let workout: WorkoutManager
    let sync: WatchSync

    @State private var selectedShoeID: UUID?
    /// Remembers the last pair used, so forgetting to pick doesn't lose
    /// wear tracking.
    @AppStorage("lastShoeID") private var lastShoeID: String = ""
    @AppStorage(ActivityClassifier.runPaceKey) private var runPaceKmh: Double = ActivityClassifier.defaultRunPaceKmh

    var body: some View {
        NavigationStack {
            startContent
        }
    }

    private var startContent: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .gaitwayGlow(Gaitway.cyan, radius: 12)
                    .background(GaitwayHalo().frame(width: 40, height: 40))

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
                            Text(shoe.pickerName).tag(UUID?.some(shoe.id))
                        }
                    }
                    .labelsHidden()
                    .frame(height: 44)
                } else {
                    Label("Shoes sync from the iPhone app", systemImage: "shoe.2")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    let shoe = sync.activeShoes.first { $0.id == selectedShoeID }
                    if let shoe {
                        lastShoeID = shoe.id.uuidString
                    }
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
                            .foregroundStyle(Gaitway.gradient)
                    }
                }
                .tint(Gaitway.cyan)
                .disabled(workout.phase == .starting)

                if let plan = sync.plannedRoute {
                    Label(
                        "Route ready · \(Format.compactDistance(plan.totalMeters))",
                        systemImage: "arrow.triangle.turn.up.right.diamond"
                    )
                    .font(.footnote)
                    .foregroundStyle(Gaitway.cyan)
                }

                Text("Walk or run — it works out which. Stops auto-pause after 5 seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                NavigationLink {
                    RunPaceSettingView()
                } label: {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundStyle(.secondary)
                        Text("Run pace: \(runPaceKmh, specifier: "%.1f") km/h")
                            .lineLimit(1)
                    }
                    .font(.footnote)
                }

            }
        }
        .onAppear {
            workout.requestLocationPermission()
            if selectedShoeID == nil {
                let remembered = UUID(uuidString: lastShoeID)
                selectedShoeID = sync.activeShoes.first { $0.id == remembered }?.id
                    ?? sync.activeShoes.first?.id
            }
        }
    }
}

/// What speed counts as running *for you* — the walk/run auto-detection
/// uses this when step cadence isn't available. Default 9 km/h.
struct RunPaceSettingView: View {
    @AppStorage(ActivityClassifier.runPaceKey) private var runPaceKmh: Double = ActivityClassifier.defaultRunPaceKmh

    var body: some View {
        VStack(spacing: 6) {
            Picker("Run pace", selection: $runPaceKmh) {
                ForEach(Array(stride(from: 6.0, through: 14.0, by: 0.5)), id: \.self) { kmh in
                    Text("\(kmh, specifier: "%.1f") km/h").tag(kmh)
                }
            }
            .frame(height: 64)

            Text("≈ \(Format.pace(3600 / runPaceKmh))/km · faster than this counts as running")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .navigationTitle("Run pace")
        .padding(.horizontal, 4)
    }
}
