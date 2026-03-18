// ABOUTME: Exact match resolution strategy for entity deduplication
// ABOUTME: Finds entities with identical names and same type, confidence 1.0

import Foundation

public struct ExactMatchStrategy: ResolutionStrategy, Sendable {
    public var name: String { "exact" }
    public var order: Int { 1 }

    public init() {}

    public func findCandidates(
        for entity: Entity,
        in entities: [Entity],
        db: AppDatabase
    ) async throws -> [ResolutionCandidate] {
        entities
            .filter { $0.id != entity.id && $0.name == entity.name && $0.kind == entity.kind }
            .map { matched in
                ResolutionCandidate(
                    entity: entity,
                    matchedEntity: matched,
                    confidence: 1.0,
                    strategy: name,
                    reason: "Exact name match: \(entity.name)"
                )
            }
    }
}
