// ABOUTME: Tests for ResolutionStrategy protocol and ExactMatchStrategy
// ABOUTME: Verifies exact name matching with same-type constraint

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func exactMatchFindsIdenticalNames() async throws {
    let db = try AppDatabase.makeInMemory()
    var e1 = Entity(name: "Harper Reed", kind: .person)
    var e2 = Entity(name: "Harper Reed", kind: .person)

    try db.write { dbConn in
        try e1.insert(dbConn)
        try e2.insert(dbConn)
    }

    let strategy = ExactMatchStrategy()
    let candidates = try await strategy.findCandidates(for: e1, in: [e1, e2], db: db)
    #expect(candidates.count == 1)
    #expect(candidates[0].confidence == 1.0)
}

@Test func exactMatchSkipsDifferentTypes() async throws {
    let db = try AppDatabase.makeInMemory()
    var e1 = Entity(name: "Apple", kind: .organization)
    var e2 = Entity(name: "Apple", kind: .concept)

    try db.write { dbConn in
        try e1.insert(dbConn)
        try e2.insert(dbConn)
    }

    let strategy = ExactMatchStrategy()
    let candidates = try await strategy.findCandidates(for: e1, in: [e1, e2], db: db)
    #expect(candidates.isEmpty)
}
