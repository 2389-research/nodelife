// ABOUTME: Orchestrates entity resolution strategies to find and merge duplicates
// ABOUTME: Auto-merges above 0.8 confidence, defers lower-confidence matches for review

import Foundation
import GRDB

public struct ResolutionReport: Sendable {
    public var entitiesBefore: Int
    public var mergesPerformed: Int
    public var mergeCount: Int { mergesPerformed }
    public var deferredCandidates: [ResolutionCandidate]

    public init(entitiesBefore: Int = 0, mergesPerformed: Int = 0, deferredCandidates: [ResolutionCandidate] = []) {
        self.entitiesBefore = entitiesBefore
        self.mergesPerformed = mergesPerformed
        self.deferredCandidates = deferredCandidates
    }
}

public actor EntityResolver {
    private let database: AppDatabase
    private let strategies: [any ResolutionStrategy]
    private let mergeEngine: MergeEngine
    private let autoMergeThreshold: Double

    public init(
        database: AppDatabase,
        strategies: [any ResolutionStrategy]? = nil,
        autoMergeThreshold: Double = 0.8
    ) {
        self.database = database
        self.strategies = strategies ?? [
            ExactMatchStrategy(),
            NormalizedMatchStrategy(),
            AliasMatchStrategy(),
            CooccurrenceStrategy()
        ]
        self.mergeEngine = MergeEngine(database: database)
        self.autoMergeThreshold = autoMergeThreshold
    }

    public func resolve() async throws -> ResolutionReport {
        let entities = try database.read { db in
            try Entity.filter(Entity.Columns.mergedIntoId == nil).fetchAll(db)
        }
        return try await resolve(entities: entities)
    }

    public func resolve(entities: [Entity]) async throws -> ResolutionReport {
        // Filter out already-merged entities to prevent merge cycles
        let activeEntities = entities.filter { $0.mergedIntoId == nil }
        var report = ResolutionReport(entitiesBefore: activeEntities.count)
        var mergedIds: Set<UUID> = []

        let sortedStrategies = strategies.sorted { $0.order < $1.order }

        for entity in activeEntities {
            guard !mergedIds.contains(entity.id) else { continue }

            let remainingEntities = activeEntities.filter { !mergedIds.contains($0.id) }

            for strategy in sortedStrategies {
                let candidates = try await strategy.findCandidates(for: entity, in: remainingEntities, db: database)

                for candidate in candidates {
                    guard !mergedIds.contains(candidate.matchedEntity.id) else { continue }

                    if candidate.confidence >= autoMergeThreshold {
                        try database.write { db in
                            try self.mergeEngine.merge(
                                primaryId: entity.id,
                                duplicateId: candidate.matchedEntity.id,
                                reason: "\(candidate.strategy): \(candidate.reason)",
                                in: db
                            )
                        }
                        mergedIds.insert(candidate.matchedEntity.id)
                        report.mergesPerformed += 1
                    } else {
                        report.deferredCandidates.append(candidate)
                    }
                }
            }
        }

        return report
    }
}
