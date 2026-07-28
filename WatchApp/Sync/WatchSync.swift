import Foundation
import Observation
import WatchConnectivity

/// The watch's half of phone↔watch sync. Receives the registered shoes via
/// application context (the phone pushes the whole list on every change)
/// and sends finished runs back with `transferUserInfo`, which queues and
/// survives the phone app not being awake — the run arrives whenever the
/// phone next gets it.
@MainActor
@Observable
final class WatchSync: NSObject, WCSessionDelegate {
    private(set) var shoes: [Shoe] = []

    private var routeStore: RouteHistoryStore?
    private let backedUpKey = "backedUpRouteIDs"

    override init() {
        super.init()
        if DemoMode.isActive {
            shoes = DemoData.shoes
            return
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        readShoes(from: WCSession.default.receivedApplicationContext)
    }

    /// Wire up route backup: every stored run mirrors to the phone (where
    /// normal iPhone/iCloud backups cover it), and an empty history —
    /// fresh or replaced watch — asks the phone to send everything back.
    func attach(routeStore: RouteHistoryStore) {
        self.routeStore = routeStore
        if routeStore.metas.isEmpty {
            WCSession.default.transferUserInfo([SyncKey.restoreRequest: true])
        }
        backupPendingRuns()
        requestShoesIfNeeded()
    }

    /// A reinstalled watch app starts with an empty received context, so
    /// the shoe list stays missing until the phone happens to push it
    /// again — ask for it instead of waiting. sendMessage wakes the
    /// phone app in the background when it's reachable; the queued
    /// transfer covers the rest.
    func requestShoesIfNeeded() {
        guard shoes.isEmpty, WCSession.default.activationState == .activated else { return }
        let payload = [SyncKey.shoesRequest: true]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(payload)
            }
        } else {
            WCSession.default.transferUserInfo(payload)
        }
    }

    func sendFavouriteUpdate(id: UUID, name: String?) {
        var info: [String: Any] = [SyncKey.favouriteID: id.uuidString]
        if let name {
            info[SyncKey.favouriteName] = name
        }
        WCSession.default.transferUserInfo(info)
    }

    /// Queue a file transfer for every run the phone doesn't have yet.
    /// Transfers survive app suspension; completion marks them done.
    func backupPendingRuns() {
        guard let routeStore, WCSession.default.activationState == .activated else { return }
        let done = backedUpIDs
        let inFlight = Set(WCSession.default.outstandingFileTransfers.compactMap {
            $0.file.metadata?[SyncKey.routeID] as? String
        })
        for meta in routeStore.metas {
            let idString = meta.id.uuidString
            guard !done.contains(idString), !inFlight.contains(idString) else { continue }
            let url = RouteHistoryStore.runURL(for: meta.id)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var metadata: [String: Any] = [
                SyncKey.fileKind: SyncKey.fileKindRouteRun,
                SyncKey.routeID: idString,
                SyncKey.routeDate: meta.date.timeIntervalSince1970,
                SyncKey.routeSeconds: meta.totalSeconds,
                SyncKey.routeMeters: meta.totalDistanceMeters,
            ]
            if let name = meta.favouriteName {
                metadata[SyncKey.favouriteName] = name
            }
            WCSession.default.transferFile(url, metadata: metadata)
        }
    }

    private var backedUpIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: backedUpKey) ?? [])
    }

    private func markBackedUp(_ idString: String) {
        var ids = backedUpIDs
        ids.insert(idString)
        UserDefaults.standard.set(Array(ids), forKey: backedUpKey)
    }

    var activeShoes: [Shoe] {
        shoes.filter { !$0.retired }.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func send(_ run: RunSummary) {
        guard let data = try? SyncCodec.encoder.encode(run) else { return }
        WCSession.default.transferUserInfo([SyncKey.run: data])
        backupPendingRuns()
    }

    private func readShoes(from context: [String: Any]) {
        guard let data = context[SyncKey.shoes] as? Data,
              let decoded = try? SyncCodec.decoder.decode([Shoe].self, from: data) else { return }
        shoes = decoded
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.readShoes(from: context)
            self.backupPendingRuns()
            self.requestShoesIfNeeded()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.readShoes(from: applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard error == nil,
              let idString = fileTransfer.file.metadata?[SyncKey.routeID] as? String else { return }
        Task { @MainActor in
            self.markBackedUp(idString)
        }
    }

    /// A restored route arriving from the phone. The incoming file must
    /// be moved before this call returns, so stash it synchronously.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let stashURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-\(UUID().uuidString).json")
        do {
            try FileManager.default.moveItem(at: file.fileURL, to: stashURL)
        } catch {
            return
        }
        let favouriteName = metadata[SyncKey.favouriteName] as? String
        let idString = metadata[SyncKey.routeID] as? String
        Task { @MainActor in
            self.routeStore?.importRun(from: stashURL, favouriteName: favouriteName)
            if let idString {
                self.markBackedUp(idString)
            }
            try? FileManager.default.removeItem(at: stashURL)
        }
    }
}
