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

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        readShoes(from: WCSession.default.receivedApplicationContext)
    }

    var activeShoes: [Shoe] {
        shoes.filter { !$0.retired }
    }

    func send(_ run: RunSummary) {
        guard let data = try? SyncCodec.encoder.encode(run) else { return }
        WCSession.default.transferUserInfo([SyncKey.run: data])
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
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.readShoes(from: applicationContext)
        }
    }
}
