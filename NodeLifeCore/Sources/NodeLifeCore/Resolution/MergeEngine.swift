// ABOUTME: Engine for merging duplicate entities, with undo and split support
// ABOUTME: Consolidates aliases, relinks relationships and mentions, and records full audit history

import Foundation
import GRDB

public enum MergeError: Error, Sendable {
    case entityNotFound
    case noMergeHistoryFound
    case mergeNotFound
    case cannotRestoreEntity
}

public struct MergeEngine: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Merge a duplicate entity into a primary entity within an existing GRDB transaction.
    /// - Snapshots duplicate data for undo
    /// - Creates alias on primary from duplicate's name
    /// - Copies duplicate's aliases to primary
    /// - Relinks relationships and mentions from duplicate to primary
    /// - Marks duplicate as merged
    /// - Records MergeHistory
    public func merge(primaryId: UUID, duplicateId: UUID, reason: String, in db: Database) throws {
        guard let primary = try Entity.fetchOne(db, key: primaryId) else {
            throw MergeError.entityNotFound
        }
        guard var duplicate = try Entity.fetchOne(db, key: duplicateId) else {
            throw MergeError.entityNotFound
        }

        // Snapshot duplicate entity, aliases, and relationships for undo
        let encoder = JSONEncoder()
        let entityData = try String(data: encoder.encode(duplicate), encoding: .utf8) ?? "{}"

        let duplicateAliases = try EntityAlias
            .filter(EntityAlias.Columns.entityID == duplicateId)
            .fetchAll(db)
        let aliasesData = try String(data: encoder.encode(duplicateAliases), encoding: .utf8)

        let duplicateRelationships = try Relationship
            .filter(Relationship.Columns.sourceEntityID == duplicateId || Relationship.Columns.targetEntityID == duplicateId)
            .fetchAll(db)
        let relationshipsData = try String(data: encoder.encode(duplicateRelationships), encoding: .utf8)

        // Add duplicate's name as alias on primary (if different)
        if duplicate.name.lowercased() != primary.name.lowercased() {
            var alias = EntityAlias(entityID: primaryId, alias: duplicate.name, source: .auto)
            try alias.insert(db)
        }

        // Copy duplicate's aliases to primary
        for existingAlias in duplicateAliases {
            var copiedAlias = EntityAlias(entityID: primaryId, alias: existingAlias.alias, source: existingAlias.source)
            try copiedAlias.insert(db)
            // Remove original alias from duplicate
            try existingAlias.delete(db)
        }

        // Relink relationships where duplicate is source
        try db.execute(
            sql: "UPDATE relationships SET sourceEntityID = ? WHERE sourceEntityID = ?",
            arguments: [primaryId, duplicateId]
        )

        // Relink relationships where duplicate is target
        try db.execute(
            sql: "UPDATE relationships SET targetEntityID = ? WHERE targetEntityID = ?",
            arguments: [primaryId, duplicateId]
        )

        // Relink mentions
        try db.execute(
            sql: "UPDATE mentions SET entityID = ? WHERE entityID = ?",
            arguments: [primaryId, duplicateId]
        )

        // Mark duplicate as merged
        duplicate.mergedIntoId = primaryId
        try duplicate.update(db)

        // Record MergeHistory
        var history = MergeHistory(
            primaryEntityId: primaryId,
            mergedEntityId: duplicateId,
            action: .merge,
            reason: reason,
            originalEntityData: entityData,
            originalAliasesData: aliasesData,
            originalRelationshipsData: relationshipsData
        )
        try history.insert(db)
    }

    /// Undo a previous merge operation, restoring the duplicate entity.
    /// - Clears mergedIntoId on the duplicate
    /// - Restores original relationships from snapshot
    /// - Records a new MergeHistory with action .undo
    public func undoMerge(historyId: UUID, in db: Database) throws {
        guard var history = try MergeHistory.fetchOne(db, key: historyId) else {
            throw MergeError.noMergeHistoryFound
        }

        guard history.action == .merge else {
            throw MergeError.mergeNotFound
        }

        // Restore duplicate entity's mergedIntoId
        guard var duplicate = try Entity.fetchOne(db, key: history.mergedEntityId) else {
            throw MergeError.cannotRestoreEntity
        }

        duplicate.mergedIntoId = nil
        try duplicate.update(db)

        // Restore original relationships from snapshot if available
        if let relData = history.originalRelationshipsData,
           let data = relData.data(using: .utf8) {
            let decoder = JSONDecoder()
            let originalRels = try decoder.decode([Relationship].self, from: data)

            // Delete only the specific relinked relationships (by their IDs),
            // preserving any relationships the primary entity had before the merge
            let relIDs = originalRels.map(\.id)
            for relID in relIDs {
                try db.execute(
                    sql: "DELETE FROM relationships WHERE id = ?",
                    arguments: [relID]
                )
            }

            // Re-insert original relationships with their original entity references
            for var rel in originalRels {
                try rel.insert(db)
            }
        }

        // Mark original history as undone
        history.undoneAt = Date()
        try history.update(db)

        // Record undo history
        var undoHistory = MergeHistory(
            primaryEntityId: history.primaryEntityId,
            mergedEntityId: history.mergedEntityId,
            action: .undo,
            reason: "Undo merge \(historyId)",
            originalEntityData: history.originalEntityData
        )
        try undoHistory.insert(db)
    }

    /// Split a previously merged entity back out.
    /// - Clears mergedIntoId on the duplicate
    /// - Removes the auto-created alias
    /// - Records a new MergeHistory with action .split
    public func split(fromMerge historyId: UUID, in db: Database) throws {
        guard let history = try MergeHistory.fetchOne(db, key: historyId) else {
            throw MergeError.noMergeHistoryFound
        }

        guard history.action == .merge else {
            throw MergeError.mergeNotFound
        }

        // Restore duplicate entity
        guard var duplicate = try Entity.fetchOne(db, key: history.mergedEntityId) else {
            throw MergeError.cannotRestoreEntity
        }

        duplicate.mergedIntoId = nil
        try duplicate.update(db)

        // Remove the auto-created alias from primary that matches duplicate's name
        let decoder = JSONDecoder()
        if let entityData = history.originalEntityData.data(using: .utf8),
           let originalEntity = try? decoder.decode(Entity.self, from: entityData) {
            try EntityAlias
                .filter(EntityAlias.Columns.entityID == history.primaryEntityId)
                .filter(EntityAlias.Columns.alias == originalEntity.name)
                .filter(EntityAlias.Columns.source == AliasSource.auto.rawValue)
                .deleteAll(db)
        }

        // Record split history
        var splitHistory = MergeHistory(
            primaryEntityId: history.primaryEntityId,
            mergedEntityId: history.mergedEntityId,
            action: .split,
            reason: "Split from merge \(historyId)",
            originalEntityData: history.originalEntityData
        )
        try splitHistory.insert(db)
    }
}
