// ABOUTME: Tests for MergeEngine merge, split, and undo operations
// ABOUTME: Verifies entity consolidation, alias transfer, relationship relinking, and history recording

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func mergeConsolidatesEntities() throws {
    let db = try AppDatabase.makeInMemory()
    let engine = MergeEngine(database: db)

    try db.write { dbConn in
        var primary = Entity(name: "Harper Reed", kind: .person)
        try primary.insert(dbConn)
        var duplicate = Entity(name: "Harper", kind: .person)
        try duplicate.insert(dbConn)

        try engine.merge(primaryId: primary.id, duplicateId: duplicate.id, reason: "exact match", in: dbConn)

        // Duplicate should be marked merged
        let dup = try Entity.fetchOne(dbConn, key: duplicate.id)
        #expect(dup?.mergedIntoId == primary.id)

        // Alias should be created
        let aliases = try EntityAlias
            .filter(EntityAlias.Columns.entityID == primary.id)
            .fetchAll(dbConn)
        #expect(aliases.contains(where: { $0.alias == "Harper" }))

        // MergeHistory should be recorded
        let history = try MergeHistory
            .filter(MergeHistory.Columns.primaryEntityId == primary.id)
            .fetchAll(dbConn)
        #expect(history.count == 1)
        #expect(history[0].action == .merge)
    }
}

@Test func mergeRelinksRelationships() throws {
    let db = try AppDatabase.makeInMemory()
    let engine = MergeEngine(database: db)

    try db.write { dbConn in
        var primary = Entity(name: "Harper Reed", kind: .person)
        try primary.insert(dbConn)
        var duplicate = Entity(name: "Harper", kind: .person)
        try duplicate.insert(dbConn)
        var other = Entity(name: "Acme", kind: .organization)
        try other.insert(dbConn)

        var meeting = Meeting(sourceID: "m1", title: "M", date: Date(), duration: 60, rawTranscript: "t", sourceAdapter: "test")
        try meeting.insert(dbConn)
        var run = ExtractionRun(meetingID: meeting.id, model: "test", promptVersion: "v1")
        try run.insert(dbConn)

        var rel = Relationship(sourceEntityID: duplicate.id, targetEntityID: other.id, kind: .worksFor, weight: 1.0, extractionRunID: run.id)
        try rel.insert(dbConn)

        try engine.merge(primaryId: primary.id, duplicateId: duplicate.id, reason: "test", in: dbConn)

        let updatedRel = try Relationship.fetchOne(dbConn, key: rel.id)
        #expect(updatedRel?.sourceEntityID == primary.id)
    }
}

@Test func undoMergeRestoresEntity() throws {
    let db = try AppDatabase.makeInMemory()
    let engine = MergeEngine(database: db)

    try db.write { dbConn in
        var primary = Entity(name: "Harper Reed", kind: .person)
        try primary.insert(dbConn)
        var duplicate = Entity(name: "Harper", kind: .person)
        try duplicate.insert(dbConn)
        let dupId = duplicate.id

        try engine.merge(primaryId: primary.id, duplicateId: dupId, reason: "test", in: dbConn)

        let history = try MergeHistory
            .filter(MergeHistory.Columns.mergedEntityId == dupId)
            .fetchOne(dbConn)!
        try engine.undoMerge(historyId: history.id, in: dbConn)

        let restored = try Entity.fetchOne(dbConn, key: dupId)
        #expect(restored?.mergedIntoId == nil)

        let undoHistory = try MergeHistory
            .filter(MergeHistory.Columns.action == MergeAction.undo.rawValue)
            .fetchAll(dbConn)
        #expect(undoHistory.count == 1)
    }
}

@Test func splitEntityCreatesNewEntity() throws {
    let db = try AppDatabase.makeInMemory()
    let engine = MergeEngine(database: db)

    try db.write { dbConn in
        var primary = Entity(name: "Harper Reed", kind: .person)
        try primary.insert(dbConn)
        var duplicate = Entity(name: "Harper", kind: .person)
        try duplicate.insert(dbConn)

        try engine.merge(primaryId: primary.id, duplicateId: duplicate.id, reason: "test", in: dbConn)

        let history = try MergeHistory
            .filter(MergeHistory.Columns.mergedEntityId == duplicate.id)
            .fetchOne(dbConn)!
        try engine.split(fromMerge: history.id, in: dbConn)

        let restored = try Entity.fetchOne(dbConn, key: duplicate.id)
        #expect(restored?.mergedIntoId == nil)
    }
}
