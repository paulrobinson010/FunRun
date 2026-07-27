import Foundation

/// Keys used in WatchConnectivity dictionaries. Application context carries
/// the shoe list phone → watch (latest state wins); user-info transfers
/// carry finished runs watch → phone (queued, delivered even if the phone
/// app is not running at the time).
enum SyncKey {
    static let shoes = "shoes"
    static let run = "run"
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
