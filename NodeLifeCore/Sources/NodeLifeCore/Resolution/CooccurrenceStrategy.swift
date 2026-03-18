// ABOUTME: Co-occurrence based entity resolution strategy using shared MeetingChunks
// ABOUTME: Matches same-named entities that appear together in at least 3 chunks

import Foundation
import GRDB

public struct CooccurrenceStrategy: ResolutionStrategy, Sendable {
    public var name: String { "cooccurrence" }
    public var order: Int { 4 }

    public let minCooccurrences: Int

    public init(minCooccurrences: Int = 3) {
        self.minCooccurrences = minCooccurrences
    }

    public func findCandidates(
        for entity: Entity,
        in entities: [Entity],
        db: AppDatabase
    ) async throws -> [ResolutionCandidate] {
        var candidates: [ResolutionCandidate] = []

        for other in entities {
            guard other.id != entity.id else { continue }
            // Only match same type
            guard other.kind == entity.kind else { continue }
            // Only match same canonical name
            guard other.canonicalName == entity.canonicalName else { continue }

            let cooccurrenceCount = try countCooccurrences(
                entityA: entity.id,
                entityB: other.id,
                db: db
            )

            if cooccurrenceCount >= minCooccurrences {
                let score = min(1.0, Double(cooccurrenceCount) / Double(minCooccurrences * 2))
                candidates.append(
                    ResolutionCandidate(
                        entity: entity,
                        matchedEntity: other,
                        confidence: score,
                        strategy: name,
                        reason: "Co-occur in \(cooccurrenceCount) chunk(s): '\(entity.name)' and '\(other.name)'"
                    )
                )
            }
        }

        return candidates
    }

    // MARK: - Private Helpers

    /// Count how many MeetingChunks both entities share via Mention records.
    private func countCooccurrences(
        entityA: UUID,
        entityB: UUID,
        db: AppDatabase
    ) throws -> Int {
        try db.read { dbConn in
            // Find chunk IDs where entityA has mentions
            let chunksA = try Mention
                .filter(Mention.Columns.entityID == entityA)
                .select(Mention.Columns.meetingChunkID, as: UUID.self)
                .fetchSet(dbConn)

            // Find chunk IDs where entityB has mentions
            let chunksB = try Mention
                .filter(Mention.Columns.entityID == entityB)
                .select(Mention.Columns.meetingChunkID, as: UUID.self)
                .fetchSet(dbConn)

            // Count the intersection
            return chunksA.intersection(chunksB).count
        }
    }
}
