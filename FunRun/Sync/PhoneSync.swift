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
        guard let data = userInfo[SyncKey.run] as? Data,
              let run = try? SyncCodec.decoder.decode(RunSummary.self, from: data) else { return }
        Task { @MainActor in
            self.onRunReceived?(run)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
