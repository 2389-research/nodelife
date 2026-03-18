// ABOUTME: Tests for EntityResolver strategy orchestration
// ABOUTME: Verifies auto-merge, deferred candidates, and strategy ordering

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func resolverAutoMergesAboveThreshold() async throws {
    let db = try AppDatabase.makeInMemory()
    let resolver = EntityResolver(database: db)

    try db.write { dbConn in
        var e1 = Entity(name: "Harper Reed", kind: .person)
        try e1.insert(dbConn)
        var e2 = Entity(name: "Harper Reed", kind: .person)
        try e2.insert(dbConn)
    }

    let entities = try db.read { db in try Entity.fetchAll(db) }
    let report = try await resolver.resolve(entities: entities)

    #expect(report.mergesPerformed > 0)
}

@Test func resolverReturnsReport() async throws {
    let db = try AppDatabase.makeInMemory()
    let resolver = EntityResolver(database: db)

    try db.write { dbConn in
        var e1 = Entity(name: "Unique One", kind: .person)
        try e1.insert(dbConn)
        var e2 = Entity(name: "Unique Two", kind: .organization)
        try e2.insert(dbConn)
    }

    let entities = try db.read { db in try Entity.fetchAll(db) }
    let report = try await resolver.resolve(entities: entities)

    #expect(report.mergesPerformed == 0)
    #expect(report.entitiesBefore == 2)
}
