import Foundation
import Observation
import UserNotifications

/// Wires the phone app together: shoes and run history on this side,
/// synced with the watch — shoes out, finished runs in.
@MainActor
@Observable
final class AppModel {
    let shoeStore = ShoeStore()
    let runLog = RunLog()
    let routeBackup = RouteBackupStore()
    let sync = PhoneSync()

    init() {
        // Screenshot/demo mode: seeded example data, no sync, nothing
        // persisted — the wiring below never attaches.
        if DemoMode.isActive {
            shoeStore.seedForDemo(DemoData.shoes)
            runLog.seedForDemo(DemoData.runs)
            return
        }
        sync.onRunReceived = { [weak self] run in
            guard let self else { return }
            runLog.add(run)
            if let change = shoeStore.apply(run) {
                notifyIfWorn(change)
            }
            pushShoes()
        }
        sync.onActivated = { [weak self] in
            self?.pushShoes()
        }
        sync.onRouteFileReceived = { [weak self] metadata in
            self?.routeBackup.record(metadata: metadata)
        }
        sync.onRestoreRequested = { [weak self] in
            guard let self else { return }
            sync.transfer(files: routeBackup.filesForRestore())
        }
        sync.onFavouriteUpdated = { [weak self] idString, name in
            self?.routeBackup.setFavourite(idString: idString, name: name)
        }
        sync.onShoesRequested = { [weak self] in
            self?.pushShoes()
        }
        pushShoes()
    }

    /// Call after any shoe change so the watch always has the latest list.
    func pushShoes() {
        sync.push(shoeStore.shoes)
    }

    /// Delete a run: the stored summary goes, and its wear comes back off
    /// the shoes it was logged against. (The HealthKit workout is
    /// untouched — that lives in Apple Health under the user's control.)
    func delete(_ run: RunSummary) {
        runLog.remove(run)
        shoeStore.revert(run)
        pushShoes()
    }

    /// Tell the user when a pair crosses 90% or 100% of its replacement
    /// distance — once per threshold, at the moment the run that crossed
    /// it arrives.
    private func notifyIfWorn(_ change: ShoeStore.WearChange) {
        let crossed = [(0.9, "is at 90% of its distance — time to think about a replacement."),
                       (1.0, "has passed its replacement distance.")]
            .filter { change.fractionBefore < $0.0 && change.fractionAfter >= $0.0 }
        guard !crossed.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            for (threshold, message) in crossed {
                let content = UNMutableNotificationContent()
                content.title = "Trainer wear"
                content.body = "\(change.shoe.displayName) \(message) (\(Int(change.shoe.distanceKm.rounded())) of \(Int(change.shoe.replaceAfterKm)) km)"
                let request = UNNotificationRequest(
                    identifier: "shoe-wear-\(change.shoe.id)-\(Int(threshold * 100))",
                    content: content,
                    trigger: nil
                )
                try? await center.add(request)
            }
        }
    }
}
