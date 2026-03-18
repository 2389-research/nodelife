// ABOUTME: Tests for NormalizedMatchStrategy entity resolution
// ABOUTME: Verifies fuzzy name matching using normalization and Levenshtein distance

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func normalizedMatchSameCaseDifferentCase() async throws {
    let db = try AppDatabase.makeInMemory()
    var e1 = Entity(name: "harper reed", kind: .person)
    var e2 = Entity(name: "Harper Reed", kind: .person)

    try db.write { dbConn in
        try e1.insert(dbConn)
        try e2.insert(dbConn)
    }

    let strategy = NormalizedMatchStrategy()
    let candidates = try await strategy.findCandidates(for: e1, in: [e1, e2], db: db)
    #expect(candidates.count == 1)
    #expect(candidates[0].confidence >= 0.8)
    #expect(candidates[0].strategy == "normalized_match")
}

@Test func normalizedMatchExtraWhitespaceAndPunctuation() async throws {
    let db = try AppDatabase.makeInMemory()
    var e1 = Entity(name: "Harper Reed", kind: .person)
    var e2 = Entity(name: "harper   reed.", kind: .person)

    try db.write { dbConn in
        try e1.insert(dbConn)
        try e2.insert(dbConn)
    }

    let strategy = NormalizedMatchStrategy()
    let candidates = try await strategy.findCandidates(for: e1, in: [e1, e2], db: db)
    #expect(candidates.count == 1)
    #expect(candidates[0].confidence >= 0.8)
}

@Test func normalizedMatchCompletelyDifferentNamesNoMatch() async throws {
    let db = try AppDatabase.makeInMemory()
    var e1 = Entity(name: "Harper Reed", kind: .person)
    var e2 = Entity(name: "Zephyr Cloudwalker", kind: .person)

    try db.write { dbConn in
        try e1.insert(dbConn)
        try e2.insert(dbConn)
    }

    let strategy = NormalizedMatchStrategy()
    let candidates = try await strategy.findCandidates(for: e1, in: [e1, e2], db: db)
    #expect(candidates.isEmpty)
}

@Test func normalizedMatchSkipsSameEntityID() async throws {
    let db = try AppDatabase.makeInMemory()
    var e1 = Entity(name: "Harper Reed", kind: .person)

    try db.write { dbConn in
        try e1.insert(dbConn)
    }

    let strategy = NormalizedMatchStrategy()
    let candidates = try await strategy.findCandidates(for: e1, in: [e1], db: db)
    #expect(candidates.isEmpty)
}

@Test func normalizedMatchOrderIs2() {
    let strategy = NormalizedMatchStrategy()
    #expect(strategy.order == 2)
    #expect(strategy.name == "normalized_match")
}
