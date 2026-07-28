import Foundation

/// Keys used in WatchConnectivity dictionaries. Application context carries
/// the shoe list phone → watch (latest state wins); user-info transfers
/// carry finished runs watch → phone (queued, delivered even if the phone
/// app is not running at the time).
enum SyncKey {
    static let shoes = "shoes"
    static let run = "run"

    /// Watch → phone: asks for every backed-up route to be sent back
    /// (fresh watch, or history wiped).
    static let restoreRequest = "restoreRequest"
    /// Watch → phone: a favourite was named/renamed/removed.
    static let favouriteID = "favouriteID"
    static let favouriteName = "favouriteName"

    // File-transfer metadata for route backups.
    static let fileKind = "kind"
    static let fileKindRouteRun = "routeRun"
    static let routeID = "routeID"
    static let routeDate = "routeDate"
    static let routeSeconds = "routeSeconds"
    static let routeMeters = "routeMeters"
}

enum SyncCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
