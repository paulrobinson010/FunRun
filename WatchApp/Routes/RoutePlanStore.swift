import Foundation

/// The planned route the phone last sent, kept until replaced or
/// cleared — a route can be followed on more than one outing.
enum RoutePlanStore {
    private static let key = "plannedRoute"

    static func load() -> PlannedRoute? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? SyncCodec.decoder.decode(PlannedRoute.self, from: data)
    }

    /// Stores only what decodes — a corrupt transfer can't wedge the
    /// start screen.
    @discardableResult
    static func save(_ data: Data) -> PlannedRoute? {
        guard let plan = try? SyncCodec.decoder.decode(PlannedRoute.self, from: data) else { return nil }
        UserDefaults.standard.set(data, forKey: key)
        return plan
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
