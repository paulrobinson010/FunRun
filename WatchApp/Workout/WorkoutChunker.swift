import Foundation

/// Turns the raw walk/run segments of a session into the workouts that get
/// saved to HealthKit. Adjacent same-mode segments merge, then any chunk
/// shorter than the gate is absorbed into its neighbours — so a token
/// 500 m jog in the middle of a long walk doesn't produce a separate
/// workout, it just becomes part of the walk. Only chunks that stand on
/// their own two feet get their own workout.
enum WorkoutChunker {
    /// A block must last this long (wall clock, so a pause inside counts
    /// towards it) to be saved as its own workout.
    static let minimumChunkDuration: TimeInterval = 5 * 60

    static func chunks(from segments: [RunSegment]) -> [RunSegment] {
        var chunks = mergeAdjacent(segments.filter { $0.end > $0.start })
        while chunks.count > 1 {
            let short = chunks.indices
                .filter { duration(chunks[$0]) < minimumChunkDuration }
                .min { duration(chunks[$0]) < duration(chunks[$1]) }
            guard let index = short else { break }
            // Absorb into the longer neighbour; mergeAdjacent then folds
            // the newly same-mode runs together, shrinking the list.
            let neighbours = [index - 1, index + 1].filter { chunks.indices.contains($0) }
            guard let target = neighbours.max(by: { duration(chunks[$0]) < duration(chunks[$1]) }) else { break }
            chunks[index].mode = chunks[target].mode
            chunks = mergeAdjacent(chunks)
        }
        return chunks
    }

    private static func duration(_ segment: RunSegment) -> TimeInterval {
        segment.end.timeIntervalSince(segment.start)
    }

    private static func mergeAdjacent(_ segments: [RunSegment]) -> [RunSegment] {
        var merged: [RunSegment] = []
        for segment in segments {
            if var last = merged.last, last.mode == segment.mode {
                last.end = segment.end
                last.distanceMeters += segment.distanceMeters
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }
        return merged
    }
}
