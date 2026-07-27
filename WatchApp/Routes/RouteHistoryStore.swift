import Foundation
import Observation
import WidgetKit

/// A stored route's headline facts — everything list UIs need without
/// touching the (much larger) point files.
struct RouteMeta: Codable, Identifiable {
    var id: UUID
    var date: Date
    var totalSeconds: TimeInterval
    var totalDistanceMeters: Double
    /// Set when the user favourites this route. Favourites are named,
    /// listed first in the ghost picker, and never pruned.
    var favouriteName: String? = nil

    var isFavourite: Bool { favouriteName != nil }
}

/// Twelve months of past routes, kept on the watch — the training data
/// for intersection predictions, segment comparisons and ghosts. Each
/// run's points live in their own file; only the small index is held in
/// memory, so a year of history doesn't weigh down app launch. Full
/// tracks load on demand (one for a ghost, all — off the main actor —
/// for the route graph).
@MainActor
@Observable
final class RouteHistoryStore {
    /// Newest first.
    private(set) var metas: [RouteMeta] = []

    static let retentionDays = 365
    private static let maximumRuns = 400

    /// Where the complication reads this week's distance from.
    static let appGroupID = "group.com.paulrobinson.FunRun"
    static let weekMetersKey = "weekMeters"

    init() {
        migrateLegacyStoreIfNeeded()
        loadIndex()
        prune()
        publishWidgetStats()
    }

    func add(_ run: RouteRun) {
        guard let data = try? SyncCodec.encoder.encode(run) else { return }
        try? data.write(to: Self.runURL(for: run.id), options: [.atomic])
        metas.insert(RouteMeta(
            id: run.id,
            date: run.date,
            totalSeconds: run.totalSeconds,
            totalDistanceMeters: run.totalDistanceMeters
        ), at: 0)
        prune()
        saveIndex()
        publishWidgetStats()
    }

    /// Push this week's distance to the shared container so the watch
    /// face complication stays current.
    private func publishWidgetStats() {
        guard let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start,
              let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        let weekMeters = metas
            .filter { $0.date >= weekStart }
            .reduce(0) { $0 + $1.totalDistanceMeters }
        defaults.set(weekMeters, forKey: Self.weekMetersKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    var favourites: [RouteMeta] {
        metas.filter(\.isFavourite).sorted { ($0.favouriteName ?? "") < ($1.favouriteName ?? "") }
    }

    /// Name (or rename) a route as a favourite; nil removes it from
    /// favourites, returning it to normal 12-month retention.
    func setFavourite(_ id: UUID, name: String?) {
        guard let index = metas.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        metas[index].favouriteName = (trimmed?.isEmpty ?? true) ? nil : trimmed
        saveIndex()
    }

    func run(withID id: UUID) -> RouteRun? {
        guard let data = try? Data(contentsOf: Self.runURL(for: id)) else { return nil }
        return try? SyncCodec.decoder.decode(RouteRun.self, from: data)
    }

    /// Every stored run, points and all. Heavy — call from off the main
    /// actor (predictor construction does).
    nonisolated static func loadAllRuns() -> [RouteRun] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: runsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? SyncCodec.decoder.decode(RouteRun.self, from: data)
            }
    }

    // MARK: - Files

    nonisolated private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    nonisolated static var runsDirectory: URL {
        let directory = applicationSupport.appendingPathComponent("routes", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated private static func runURL(for id: UUID) -> URL {
        runsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private static var indexURL: URL {
        applicationSupport.appendingPathComponent("route-index.json")
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: Self.indexURL),
              let decoded = try? SyncCodec.decoder.decode([RouteMeta].self, from: data) else { return }
        metas = decoded.sorted { $0.date > $1.date }
    }

    private func saveIndex() {
        guard let data = try? SyncCodec.encoder.encode(metas) else { return }
        try? data.write(to: Self.indexURL, options: [.atomic])
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        var keep: [RouteMeta] = []
        var dropped: [RouteMeta] = []
        var ordinaryCount = 0
        for meta in metas {
            if meta.isFavourite {
                keep.append(meta)
            } else if meta.date >= cutoff, ordinaryCount < Self.maximumRuns {
                keep.append(meta)
                ordinaryCount += 1
            } else {
                dropped.append(meta)
            }
        }
        guard !dropped.isEmpty else { return }
        metas = keep
        for meta in dropped {
            try? FileManager.default.removeItem(at: Self.runURL(for: meta.id))
        }
        saveIndex()
    }

    /// One-time split of the original single-file store into per-run
    /// files plus index.
    private func migrateLegacyStoreIfNeeded() {
        let legacyURL = Self.applicationSupport.appendingPathComponent("route-history.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path),
              !FileManager.default.fileExists(atPath: Self.indexURL.path),
              let data = try? Data(contentsOf: legacyURL),
              let runs = try? SyncCodec.decoder.decode([RouteRun].self, from: data) else { return }
        var migrated: [RouteMeta] = []
        for run in runs {
            guard let encoded = try? SyncCodec.encoder.encode(run) else { continue }
            try? encoded.write(to: Self.runURL(for: run.id), options: [.atomic])
            migrated.append(RouteMeta(
                id: run.id,
                date: run.date,
                totalSeconds: run.totalSeconds,
                totalDistanceMeters: run.totalDistanceMeters
            ))
        }
        metas = migrated.sorted { $0.date > $1.date }
        saveIndex()
        try? FileManager.default.removeItem(at: legacyURL)
    }
}
