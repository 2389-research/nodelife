// ABOUTME: Alias-based entity resolution strategy using the EntityAlias table
// ABOUTME: Matches entities whose name appears as another entity's alias

import Foundation
import GRDB

public struct AliasMatchStrategy: ResolutionStrategy, Sendable {
    public var name: String { "alias_match" }
    public var order: Int { 3 }

    public init() {}

    public func findCandidates(
        for entity: Entity,
        in entities: [Entity],
        db: AppDatabase
    ) async throws -> [ResolutionCandidate] {
        var candidates: [ResolutionCandidate] = []

        // Build a lookup of entity names to entities (excluding current entity)
        var nameToEntities: [String: [Entity]] = [:]
        for other in entities where other.id != entity.id {
            nameToEntities[other.name, default: []].append(other)
        }

        // Check if entity's name matches any alias of other entities
        let aliasMatches: [EntityAlias] = try db.read { dbConn in
            try EntityAlias
                .filter(EntityAlias.Columns.alias == entity.name)
                .fetchAll(dbConn)
        }

        for alias in aliasMatches {
            // Find the entity that owns this alias, if it's in our list
            if let matched = entities.first(where: { $0.id == alias.entityID && $0.id != entity.id && $0.kind == entity.kind }) {
                candidates.append(
                    ResolutionCandidate(
                        entity: entity,
                        matchedEntity: matched,
                        confidence: 1.0,
                        strategy: name,
                        reason: "Alias match: '\(entity.name)' is an alias of '\(matched.name)'"
                    )
                )
            }
        }

        // Check if any other entity's name matches an alias of this entity
        let entityAliases: [EntityAlias] = try db.read { dbConn in
            try EntityAlias
                .filter(EntityAlias.Columns.entityID == entity.id)
                .fetchAll(dbConn)
        }

        for alias in entityAliases {
            if let matchedEntities = nameToEntities[alias.alias] {
                for matched in matchedEntities where matched.kind == entity.kind {
                    // Avoid duplicate pairs
                    let alreadyFound = candidates.contains { $0.matchedEntity.id == matched.id }
                    guard !alreadyFound else { continue }

                    candidates.append(
                        ResolutionCandidate(
                            entity: entity,
                            matchedEntity: matched,
                            confidence: 1.0,
                            strategy: name,
                            reason: "Alias match: '\(entity.name)' has alias '\(alias.alias)' matching '\(matched.name)'"
                        )
                    )
                }
            }
        }

        return candidates
    }
}
