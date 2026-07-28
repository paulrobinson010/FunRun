import Foundation
import Observation

/// The phone's mirror of the watch's route history. Files land here via
/// WatchConnectivity file transfers and sit in Application Support, so
/// standard iPhone/iCloud backups cover them — replace the watch and it
/// asks for everything back; replace the phone and iCloud restores this
/// store first.
@MainActor
@Observable
final class RouteBackupStore {
    struct Entry: Codable, Identifiable {
        var id: UUID
        var date: Date
        var totalSeconds: TimeInterval
        var totalDistanceMeters: Double
        var favouriteName: String?
    }

    private(set) var entries: [Entry] = []

    init() {
        load()
    }

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("route-backup", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    nonisolated static func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Index a route file that just arrived (the sync layer has already
    /// moved it into place).
    func record(metadata: [String: Any]) {
        guard let idString = metadata[SyncKey.routeID] as? String,
              let id = UUID(uuidString: idString) else { return }
        let entry = Entry(
            id: id,
            date: Date(timeIntervalSince1970: metadata[SyncKey.routeDate] as? Double ?? 0),
            totalSeconds: metadata[SyncKey.routeSeconds] as? Double ?? 0,
            totalDistanceMeters: metadata[SyncKey.routeMeters] as? Double ?? 0,
            favouriteName: metadata[SyncKey.favouriteName] as? String
        )
        entries.removeAll { $0.id == id }
        entries.append(entry)
        entries.sort { $0.date > $1.date }
        save()
    }

    func setFavourite(idString: String, name: String?) {
        guard let id = UUID(uuidString: idString),
              let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].favouriteName = name
        save()
    }

    /// Everything needed to rebuild a watch from scratch.
    func filesForRestore() -> [(url: URL, metadata: [String: Any])] {
        entries.compactMap { entry in
            let url = Self.fileURL(for: entry.id)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            var metadata: [String: Any] = [
                SyncKey.fileKind: SyncKey.fileKindRouteRun,
                SyncKey.routeID: entry.id.uuidString,
                SyncKey.routeDate: entry.date.timeIntervalSince1970,
                SyncKey.routeSeconds: entry.totalSeconds,
                SyncKey.routeMeters: entry.totalDistanceMeters,
            ]
            if let name = entry.favouriteName {
                metadata[SyncKey.favouriteName] = name
            }
            return (url, metadata)
        }
    }

    // MARK: - Persistence

    private var indexURL: URL {
        Self.directory.appendingPathComponent("index.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        entries = (try? SyncCodec.decoder.decode([Entry].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? SyncCodec.encoder.encode(entries) else { return }
        try? data.write(to: indexURL, options: [.atomic])
    }
}
