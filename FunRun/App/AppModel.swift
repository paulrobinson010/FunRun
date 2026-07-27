import Foundation
import Observation

/// Wires the phone app together: shoes and run history on this side,
/// synced with the watch — shoes out, finished runs in.
@MainActor
@Observable
final class AppModel {
    let shoeStore = ShoeStore()
    let runLog = RunLog()
    let sync = PhoneSync()

    init() {
        sync.onRunReceived = { [weak self] run in
            guard let self else { return }
            runLog.add(run)
            shoeStore.apply(run)
            pushShoes()
        }
        sync.onActivated = { [weak self] in
            self?.pushShoes()
        }
        pushShoes()
    }

    /// Call after any shoe change so the watch always has the latest list.
    func pushShoes() {
        sync.push(shoeStore.shoes)
    }
}
