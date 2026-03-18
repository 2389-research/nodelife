// ABOUTME: Tests for GraphBuilder projection materialization from database
// ABOUTME: Verifies full, semantic, cooccurrence, and ego graph projections

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func buildFullGraphFromEntities() async throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var e1 = Entity(name: "Harper", kind: .person)
        try e1.insert(dbConn)
        var e2 = Entity(name: "Acme", kind: .organization)
        try e2.insert(dbConn)

        var meeting = Meeting(sourceID: "g1", title: "M", date: Date(), duration: 60, rawTranscript: "t", sourceAdapter: "test")
        try meeting.insert(dbConn)
        var run = ExtractionRun(meetingID: meeting.id, model: "test", promptVersion: "v1")
        try run.insert(dbConn)

        var rel = Relationship(sourceEntityID: e1.id, targetEntityID: e2.id, kind: .worksFor, weight: 1.0, extractionRunID: run.id)
        try rel.insert(dbConn)
    }

    let builder = GraphBuilder(database: db)
    let projection = try await builder.build(projectionType: .full, filter: .default)
    #expect(projection.nodes.count == 2)
    #expect(projection.edges.count == 1)
    #expect(projection.projectionType == .full)
}

@Test func buildSemanticGraphExcludesCooccurrence() async throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var e1 = Entity(name: "A", kind: .person)
        try e1.insert(dbConn)
        var e2 = Entity(name: "B", kind: .person)
        try e2.insert(dbConn)

        var meeting = Meeting(sourceID: "g2", title: "M", date: Date(), duration: 60, rawTranscript: "t", sourceAdapter: "test")
        try meeting.insert(dbConn)
        var run = ExtractionRun(meetingID: meeting.id, model: "test", promptVersion: "v1")
        try run.insert(dbConn)

        var semRel = Relationship(sourceEntityID: e1.id, targetEntityID: e2.id, kind: .collaborates, weight: 1.0, extractionRunID: run.id)
        try semRel.insert(dbConn)
        var coRel = Relationship(sourceEntityID: e1.id, targetEntityID: e2.id, kind: .cooccurs, weight: 0.5, extractionRunID: run.id)
        try coRel.insert(dbConn)
    }

    let builder = GraphBuilder(database: db)
    let projection = try await builder.build(projectionType: .semantic, filter: .default)
    #expect(projection.edges.count == 1)
    #expect(projection.edges[0].type == .collaborates)
}

@Test func buildEgoGraphFindsNeighbors() async throws {
    let db = try AppDatabase.makeInMemory()
    var centerId = UUID()

    try db.write { dbConn in
        var center = Entity(name: "Center", kind: .person)
        try center.insert(dbConn)
        centerId = center.id

        var neighbor = Entity(name: "Neighbor", kind: .organization)
        try neighbor.insert(dbConn)
        var distant = Entity(name: "Distant", kind: .concept)
        try distant.insert(dbConn)

        var meeting = Meeting(sourceID: "g3", title: "M", date: Date(), duration: 60, rawTranscript: "t", sourceAdapter: "test")
        try meeting.insert(dbConn)
        var run = ExtractionRun(meetingID: meeting.id, model: "test", promptVersion: "v1")
        try run.insert(dbConn)

        var rel = Relationship(sourceEntityID: center.id, targetEntityID: neighbor.id, kind: .worksFor, weight: 1.0, extractionRunID: run.id)
        try rel.insert(dbConn)
        // distant has no connection to center
    }

    let builder = GraphBuilder(database: db)
    let projection = try await builder.build(projectionType: .ego(entityID: centerId, depth: 1), filter: .default)
    #expect(projection.nodes.count == 2) // center + neighbor, not distant
}

@Test func filterExcludesMergedEntities() async throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var e1 = Entity(name: "Active", kind: .person)
        try e1.insert(dbConn)
        var e2 = Entity(name: "Merged", kind: .person, mergedIntoId: e1.id)
        try e2.insert(dbConn)
    }

    let builder = GraphBuilder(database: db)
    let projection = try await builder.build(projectionType: .full, filter: .default)
    #expect(projection.nodes.count == 1)
    #expect(projection.nodes[0].label == "Active")
}
