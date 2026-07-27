import SwiftUI

/// Pick a pair of trainers (synced from the phone) and go. Runs without a
/// shoe are fine too — wear just isn't attributed anywhere.
struct StartView: View {
    let workout: WorkoutManager
    let sync: WatchSync

    @State private var selectedShoeID: UUID?
    @State private var selectedGhostID: UUID?
    /// Remembers the last pair used, so forgetting to pick doesn't lose
    /// wear tracking.
    @AppStorage("lastShoeID") private var lastShoeID: String = ""

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
                        GhostPickerView(workout: workout, selectedID: $selectedGhostID)
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
                    if let shoe {
                        lastShoeID = shoe.id.uuidString
                    }
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
                let remembered = UUID(uuidString: lastShoeID)
                selectedShoeID = sync.activeShoes.first { $0.id == remembered }?.id
                    ?? sync.activeShoes.first?.id
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

/// Routes to race: named favourites first, then the last 12 months,
/// newest first. Swipe a route to favourite (and name) it, swipe a
/// favourite to rename or remove it.
struct GhostPickerView: View {
    let workout: WorkoutManager
    @Binding var selectedID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var naming: RouteMeta?

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

            let favourites = workout.ghostCandidates.filter(\.isFavourite)
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
                ForEach(workout.ghostCandidates.filter { !$0.isFavourite }) { meta in
                    routeRow(meta, title: meta.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                        .swipeActions {
                            Button {
                                naming = meta
                            } label: {
                                Image(systemName: "star.fill")
                            }
                            .tint(.yellow)
                        }
                }
            }
        }
        .navigationTitle("Ghost")
        .sheet(item: $naming) { meta in
            FavouriteNameView(meta: meta) { name in
                workout.setFavourite(routeID: meta.id, name: name)
            }
        }
    }

    private func routeRow(_ meta: RouteMeta, title: String) -> some View {
        Button {
            selectedID = meta.id
            dismiss()
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

extension RouteMeta {
    /// The favourite's name, or "22 Jul 25 · 7.51 km" — enough to
    /// recognise a route by.
    var ghostLabel: String {
        if let favouriteName {
            return favouriteName
        }
        let day = date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
        return "\(day) · \(Format.distance(totalDistanceMeters))"
    }
}
