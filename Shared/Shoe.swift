import Foundation

/// A registered pair of trainers. The phone is the source of truth: shoes
/// are created and edited there, mirrored to the watch for picking at the
/// start of a run, and their wear accumulates as finished runs sync back.
struct Shoe: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var brand: String
    var addedAt: Date = Date()
    /// Distance at which this pair should be replaced. Most trainers are
    /// good for 500–800 km; default sits in the middle.
    var replaceAfterKm: Double = 650
    /// Total distance run or walked in this pair, in metres.
    var distanceMeters: Double = 0
    var retired: Bool = false
    /// Colourway — optional so older stored shoes decode unchanged.
    var color: String? = nil

    var distanceKm: Double { distanceMeters / 1000 }

    /// 0…1+ — how far through its life this pair is (can exceed 1).
    var wearFraction: Double {
        guard replaceAfterKm > 0 else { return 0 }
        return distanceKm / replaceAfterKm
    }

    var displayName: String {
        brand.isEmpty ? name : "\(brand) \(name)"
    }

    /// Picker label: colour included so two identical pairs in different
    /// colourways stay tellable apart.
    var pickerName: String {
        guard let color, !color.isEmpty else { return displayName }
        return "\(displayName) · \(color)"
    }
}
