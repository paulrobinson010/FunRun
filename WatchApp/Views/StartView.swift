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
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

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
                    }
                }
                .tint(.green)
                .disabled(workout.phase == .starting)

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

                if !workout.savedRoutes.isEmpty {
                    NavigationLink {
                        RoutesView(workout: workout)
                    } label: {
                        HStack {
                            Image(systemName: "star")
                                .foregroundStyle(.yellow)
                            Text("Routes")
                        }
                        .font(.footnote)
                    }
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

/// Stored routes: named favourites first, then the last 12 months,
/// newest first. Tap a route to favourite (and name) it; swipe a
/// favourite to rename or remove it. Favourites carry their names to
/// the phone backup.
struct RoutesView: View {
    let workout: WorkoutManager

    @State private var naming: RouteMeta?

    var body: some View {
        List {
            let favourites = workout.savedRoutes.filter(\.isFavourite)
                .sorted { ($0.favouriteName ?? "") < ($1.favouriteName ?? "") }
            if !favourites.isEmpty {
                Section("Favourites") {
                    ForEach(favourites) { meta in
                        routeRow(meta, title: meta.favouriteName ?? "")
                            .swipeActions {
                                Button {
                                    naming = meta
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                Button(role: .destructive) {
                                    workout.setFavourite(routeID: meta.id, name: nil)
                                } label: {
                                    Image(systemName: "star.slash")
                                }
                            }
                    }
                }
            }

            Section("Recent") {
                ForEach(workout.savedRoutes.filter { !$0.isFavourite }) { meta in
                    routeRow(meta, title: meta.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                }
            }
        }
        .navigationTitle("Routes")
        .sheet(item: $naming) { meta in
            FavouriteNameView(meta: meta) { name in
                workout.setFavourite(routeID: meta.id, name: name)
            }
        }
    }

    private func routeRow(_ meta: RouteMeta, title: String) -> some View {
        Button {
            naming = meta
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if meta.isFavourite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(title)
                        .lineLimit(1)
                    Spacer()
                }
                Text("\(Format.distance(meta.totalDistanceMeters)) · \(Format.duration(meta.totalSeconds))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Name a favourite route — dictation, scribble or keyboard.
struct FavouriteNameView: View {
    let meta: RouteMeta
    let save: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(meta: RouteMeta, save: @escaping (String) -> Void) {
        self.meta = meta
        self.save = save
        _name = State(initialValue: meta.favouriteName ?? "\(Format.distance(meta.totalDistanceMeters)) loop")
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("Route name", text: $name)
            Button {
                save(name)
                dismiss()
            } label: {
                Label("Save", systemImage: "star.fill")
            }
            .tint(.yellow)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 4)
    }
}

