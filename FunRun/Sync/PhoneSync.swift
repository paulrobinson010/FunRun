import Foundation
import Observation
import WatchConnectivity

/// The phone's half of phone↔watch sync: pushes the full shoe list as
/// application context whenever it changes, and receives finished runs as
/// queued user-info transfers from the watch.
@MainActor
@Observable
final class PhoneSync: NSObject, WCSessionDelegate {
    var onRunReceived: ((RunSummary) -> Void)?
    /// Fires once the session activates, so the shoe list can be pushed —
    /// a push attempted before activation is dropped by WatchConnectivity.
    var onActivated: (() -> Void)?
    /// A route backup file arrived (already moved into the backup
    /// directory); metadata describes it.
    var onRouteFileReceived: (([String: Any]) -> Void)?
    /// The watch has empty history and wants everything back.
    var onRestoreRequested: (() -> Void)?
    /// A favourite was named/renamed/removed on the watch.
    var onFavouriteUpdated: ((String, String?) -> Void)?
    /// The watch lost its shoe list (reinstall) and wants it re-pushed.
    var onShoesRequested: (() -> Void)?

    /// Send backed-up routes to the watch (restore).
    func transfer(files: [(url: URL, metadata: [String: Any])]) {
        guard WCSession.default.activationState == .activated else { return }
        for file in files {
            WCSession.default.transferFile(file.url, metadata: file.metadata)
        }
    }

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func push(_ shoes: [Shoe]) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let data = try? SyncCodec.encoder.encode(shoes) else { return }
        try? WCSession.default.updateApplicationContext([SyncKey.shoes: data])
    }

    /// Queue a planned route for the watch — latest one wins there.
    func send(plannedRoute: PlannedRoute) {
        guard WCSession.default.activationState == .activated,
              let data = try? SyncCodec.encoder.encode(plannedRoute) else { return }
        WCSession.default.transferUserInfo([SyncKey.plannedRoute: data])
    }

    func clearPlannedRoute() {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([SyncKey.clearPlannedRoute: true])
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.onActivated?()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[SyncKey.run] as? Data,
           let run = try? SyncCodec.decoder.decode(RunSummary.self, from: data) {
            Task { @MainActor in
                self.onRunReceived?(run)
            }
        } else if userInfo[SyncKey.restoreRequest] != nil {
            Task { @MainActor in
                self.onRestoreRequested?()
            }
        } else if userInfo[SyncKey.shoesRequest] != nil {
            Task { @MainActor in
                self.onShoesRequested?()
            }
        } else if let idString = userInfo[SyncKey.favouriteID] as? String {
            let name = userInfo[SyncKey.favouriteName] as? String
            Task { @MainActor in
                self.onFavouriteUpdated?(idString, name)
            }
        }
    }

    /// A route backup arriving from the watch. The incoming file must be
    /// moved before this call returns.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        guard metadata[SyncKey.fileKind] as? String == SyncKey.fileKindRouteRun,
              let idString = metadata[SyncKey.routeID] as? String,
              let id = UUID(uuidString: idString) else { return }
        let destination = RouteBackupStore.fileURL(for: id)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: file.fileURL, to: destination)
        } catch {
            return
        }
        Task { @MainActor in
            self.onRouteFileReceived?(metadata)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message[SyncKey.shoesRequest] != nil {
            Task { @MainActor in
                self.onShoesRequested?()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
