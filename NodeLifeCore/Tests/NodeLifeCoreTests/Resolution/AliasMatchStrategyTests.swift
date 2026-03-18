// ABOUTME: Tests for AliasMatchStrategy entity resolution
// ABOUTME: Verifies matching entities via the EntityAlias table

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func aliasMatchFindsEntityByAlias() async throws {
    let db = try AppDatabase.makeInMemory()
    var e1 = Entity(name: "Harp Dog", kind: .person)
    var e2 = Entity(name: "Harper Reed", kind: .person)

    try db.write { dbConn in
        try e1.insert(dbConn)
        try e2.insert(dbConn)
    }

    // e2 has an alias "Harp Dog" which matches e1's name
    var alias = EntityAlias(entityID: e2.id, alias: "Harp Dog", source: .auto)
    try db.write { dbConn in
        try alias.insert(dbConn)
    }

    let strategy = AliasMatchStrategy()
    let candidates = try await strategy.findCandidates(for: e1, in: [e1, e2], db: db)
    #expect(candidates.count == 1)
    #expect(candidates[0].confidence == 1.0)
    #expect(candidates[0].strategy == "alias_match")
    #expect(candidates[0].matchedEntity.id == e2.id)
}

@Test func aliasMatchNoAliasReturnsEmpty() async throws {
    let db = try AppDatabase.makeInMemory()
    var e1 = Entity(name: "Harper Reed", kind: .person)
    var e2 = Entity(name: "Someone Else", kind: .person)

    try db.write { dbConn in
        try e1.insert(dbConn)
        try e2.insert(dbConn)
    }

    let strategy = AliasMatchStrategy()
    let candidates = try await strategy.findCandidates(for: e1, in: [e1, e2], db: db)
    #expect(candidates.isEmpty)
}

@Test func aliasMatchOrderIs3() {
    let strategy = AliasMatchStrategy()
    #expect(strategy.order == 3)
    #expect(strategy.name == "alias_match")
}
