import Foundation
import Observation

/// Past routes, kept on the watch — this is the training data for
/// intersection predictions, so it lives where the predictions happen.
/// Capped to the most recent runs to bound file size and keep predictions
/// reflecting current habits and fitness.
@MainActor
@Observable
final class RouteHistoryStore {
    private(set) var runs: [RouteRun] = []

    private let maximumRuns = 120

    init() {
        load()
    }

    func add(_ run: RouteRun) {
        runs.append(run)
        if runs.count > maximumRuns {
            runs.removeFirst(runs.count - maximumRuns)
        }
        save()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("route-history.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        runs = (try? SyncCodec.decoder.decode([RouteRun].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? SyncCodec.encoder.encode(runs) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
