import Foundation
import Observation

/// Registered trainers and their accumulated wear. The phone owns this
/// list; every change is pushed to the watch by AppModel. Wear grows as
/// runs arrive from the watch — each run is applied at most once, so a
/// re-delivered transfer can't double-count distance.
@MainActor
@Observable
final class ShoeStore {
    private(set) var shoes: [Shoe] = []

    private var appliedRunIDs: Set<UUID> = []

    init() {
        load()
    }

    var active: [Shoe] { shoes.filter { !$0.retired } }
    var retired: [Shoe] { shoes.filter { $0.retired } }

    func add(_ shoe: Shoe) {
        shoes.append(shoe)
        save()
    }

    func update(_ shoe: Shoe) {
        guard let index = shoes.firstIndex(where: { $0.id == shoe.id }) else { return }
        shoes[index] = shoe
        save()
    }

    func remove(_ shoe: Shoe) {
        shoes.removeAll { $0.id == shoe.id }
        save()
    }

    /// Add a finished run's distance to the shoes it was done in.
    func apply(_ run: RunSummary) {
        guard !appliedRunIDs.contains(run.id) else { return }
        appliedRunIDs.insert(run.id)
        if let shoeID = run.shoeID, let index = shoes.firstIndex(where: { $0.id == shoeID }) {
            shoes[index].distanceMeters += run.distanceMeters
        }
        save()
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var shoes: [Shoe]
        var appliedRunIDs: Set<UUID>
    }

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("shoes.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? SyncCodec.decoder.decode(Snapshot.self, from: data) else { return }
        shoes = snapshot.shoes
        appliedRunIDs = snapshot.appliedRunIDs
    }

    private func save() {
        let snapshot = Snapshot(shoes: shoes, appliedRunIDs: appliedRunIDs)
        guard let data = try? SyncCodec.encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
