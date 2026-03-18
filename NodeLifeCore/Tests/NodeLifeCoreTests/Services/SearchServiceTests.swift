// ABOUTME: Tests for the SearchService full-text search across meetings, chunks, and entities
// ABOUTME: Verifies chunk search, entity search, meeting search, empty queries, and result ranking

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func searchFindsChunksByText() async throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var meeting = Meeting(
            sourceID: "s1", title: "Roadmap", date: Date(),
            duration: 60, rawTranscript: "test", sourceAdapter: "test"
        )
        try meeting.insert(dbConn)
        var chunk = MeetingChunk(
            meetingID: meeting.id, chunkIndex: 0,
            text: "We discussed the product roadmap for Q3"
        )
        try chunk.insert(dbConn)
    }

    let service = SearchService(database: db)
    let results = try await service.search(query: "roadmap")

    #expect(!results.isEmpty)
    #expect(results.first?.type == .meetingChunk)
    #expect(results.first?.snippet.contains("roadmap") == true)
}

@Test func searchFindsEntitiesByName() async throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var entity = Entity(name: "Harper Reed", kind: .person)
        try entity.insert(dbConn)
    }

    let service = SearchService(database: db)
    let results = try await service.search(query: "Harper")

    #expect(!results.isEmpty)
    #expect(results.first?.type == .entity)
    #expect(results.first?.title == "Harper Reed")
}

@Test func searchFindsMeetingsByTitle() async throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var meeting = Meeting(
            sourceID: "s1", title: "Weekly Planning Meeting", date: Date(),
            duration: 3600, rawTranscript: "transcript", sourceAdapter: "test"
        )
        try meeting.insert(dbConn)
    }

    let service = SearchService(database: db)
    let results = try await service.search(query: "Planning")

    #expect(!results.isEmpty)
    #expect(results.first?.type == .meeting)
    #expect(results.first?.title == "Weekly Planning Meeting")
}

@Test func searchReturnsEmptyForNoMatch() async throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var meeting = Meeting(
            sourceID: "s1", title: "Test Meeting", date: Date(),
            duration: 60, rawTranscript: "test", sourceAdapter: "test"
        )
        try meeting.insert(dbConn)
    }

    let service = SearchService(database: db)
    let results = try await service.search(query: "nonexistent")
    #expect(results.isEmpty)
}

@Test func searchHandlesEmptyQuery() async throws {
    let db = try AppDatabase.makeInMemory()
    let service = SearchService(database: db)

    let results = try await service.search(query: "")
    #expect(results.isEmpty)
}

@Test func searchHandlesWhitespaceQuery() async throws {
    let db = try AppDatabase.makeInMemory()
    let service = SearchService(database: db)

    let results = try await service.search(query: "   ")
    #expect(results.isEmpty)
}

@Test func searchResultsSortedByRelevance() async throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        // Create a meeting with a matching title and a matching chunk
        var meeting = Meeting(
            sourceID: "s1", title: "Architecture Review", date: Date(),
            duration: 60, rawTranscript: "test", sourceAdapter: "test"
        )
        try meeting.insert(dbConn)
        var chunk = MeetingChunk(
            meetingID: meeting.id, chunkIndex: 0,
            text: "The architecture needs to be reviewed"
        )
        try chunk.insert(dbConn)
        // Create an entity with matching name
        var entity = Entity(name: "Architecture Team", kind: .organization)
        try entity.insert(dbConn)
    }

    let service = SearchService(database: db)
    let results = try await service.search(query: "Architecture")

    #expect(results.count == 3)
    // Chunks have highest relevance (1.0), then meetings (0.9), then entities (0.8)
    #expect(results[0].type == .meetingChunk)
    #expect(results[1].type == .meeting)
    #expect(results[2].type == .entity)
}

@Test func searchIsCaseInsensitive() async throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var entity = Entity(name: "ACME Corporation", kind: .organization)
        try entity.insert(dbConn)
    }

    let service = SearchService(database: db)
    let results = try await service.search(query: "acme")

    #expect(!results.isEmpty)
    #expect(results.first?.title == "ACME Corporation")
}

@Test func searchRespectsLimit() async throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var meeting = Meeting(
            sourceID: "s1", title: "Test", date: Date(),
            duration: 60, rawTranscript: "test", sourceAdapter: "test"
        )
        try meeting.insert(dbConn)
        for i in 0..<10 {
            var chunk = MeetingChunk(
                meetingID: meeting.id, chunkIndex: i,
                text: "Chunk number \(i) about testing stuff"
            )
            try chunk.insert(dbConn)
        }
    }

    let service = SearchService(database: db)
    let results = try await service.search(query: "testing", limit: 3)

    #expect(results.count == 3)
}

@Test func searchChunkIncludesMeetingContext() async throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var meeting = Meeting(
            sourceID: "s1", title: "Sprint Planning", date: Date(),
            duration: 60, rawTranscript: "test", sourceAdapter: "test"
        )
        try meeting.insert(dbConn)
        var chunk = MeetingChunk(
            meetingID: meeting.id, chunkIndex: 0,
            text: "We need to plan the sprint backlog", speaker: "Alice"
        )
        try chunk.insert(dbConn)
    }

    let service = SearchService(database: db)
    let results = try await service.search(query: "sprint")

    let chunkResult = results.first { $0.type == .meetingChunk }
    #expect(chunkResult != nil)
    #expect(chunkResult?.title == "Sprint Planning")
    #expect(chunkResult?.context == "Speaker: Alice")
    #expect(chunkResult?.meetingID != nil)
}
