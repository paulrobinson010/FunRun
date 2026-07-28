import Foundation
import Observation

/// Every run synced over from the watch, newest first.
@MainActor
@Observable
final class RunLog {
    private(set) var runs: [RunSummary] = []

    init() {
        load()
    }

    func add(_ run: RunSummary) {
        guard !runs.contains(where: { $0.id == run.id }) else { return }
        runs.append(run)
        runs.sort { $0.startDate > $1.startDate }
        save()
    }

    func remove(_ run: RunSummary) {
        runs.removeAll { $0.id == run.id }
        save()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("runs.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        runs = (try? SyncCodec.decoder.decode([RunSummary].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? SyncCodec.encoder.encode(runs) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
