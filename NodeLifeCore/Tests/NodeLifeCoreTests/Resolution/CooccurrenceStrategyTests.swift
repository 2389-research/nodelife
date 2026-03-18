// ABOUTME: Tests for CooccurrenceStrategy entity resolution
// ABOUTME: Verifies matching entities that co-occur in the same MeetingChunks

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func cooccurrenceMatchesEntitiesInSameChunks() async throws {
    let db = try AppDatabase.makeInMemory()

    // Create a meeting
    var meeting = Meeting(
        sourceID: "test-meeting-1",
        title: "Test Meeting",
        date: Date(),
        duration: 3600,
        rawTranscript: "Some transcript",
        sourceAdapter: "test"
    )
    try db.write { dbConn in
        try meeting.insert(dbConn)
    }

    // Create an extraction run
    var run = ExtractionRun(
        meetingID: meeting.id,
        model: "test-model",
        promptVersion: "v1"
    )
    try db.write { dbConn in
        try run.insert(dbConn)
    }

    // Create two entities with the same canonical name but different surface names
    var e1 = Entity(name: "Harper", kind: .person)
    var e2 = Entity(name: "Harper", kind: .person)

    try db.write { dbConn in
        try e1.insert(dbConn)
        try e2.insert(dbConn)
    }

    // Create 3 chunks and mention both entities in each chunk
    for i in 0..<3 {
        var chunk = MeetingChunk(meetingID: meeting.id, chunkIndex: i, text: "Chunk \(i)")
        try db.write { dbConn in
            try chunk.insert(dbConn)
        }

        var m1 = Mention(entityID: e1.id, meetingChunkID: chunk.id, confidence: 0.9, extractionRunID: run.id)
        var m2 = Mention(entityID: e2.id, meetingChunkID: chunk.id, confidence: 0.9, extractionRunID: run.id)
        try db.write { dbConn in
            try m1.insert(dbConn)
            try m2.insert(dbConn)
        }
    }

    let strategy = CooccurrenceStrategy()
    let candidates = try await strategy.findCandidates(for: e1, in: [e1, e2], db: db)
    #expect(candidates.count == 1)
    #expect(candidates[0].confidence > 0)
    #expect(candidates[0].strategy == "cooccurrence")
}

@Test func cooccurrenceNoMatchInDifferentChunks() async throws {
    let db = try AppDatabase.makeInMemory()

    var meeting = Meeting(
        sourceID: "test-meeting-2",
        title: "Test Meeting 2",
        date: Date(),
        duration: 3600,
        rawTranscript: "Some transcript",
        sourceAdapter: "test"
    )
    try db.write { dbConn in
        try meeting.insert(dbConn)
    }

    var run = ExtractionRun(
        meetingID: meeting.id,
        model: "test-model",
        promptVersion: "v1"
    )
    try db.write { dbConn in
        try run.insert(dbConn)
    }

    var e1 = Entity(name: "Harper", kind: .person)
    var e2 = Entity(name: "Harper", kind: .person)

    try db.write { dbConn in
        try e1.insert(dbConn)
        try e2.insert(dbConn)
    }

    // Put them in DIFFERENT chunks (no overlap)
    var chunk1 = MeetingChunk(meetingID: meeting.id, chunkIndex: 0, text: "Chunk 0")
    var chunk2 = MeetingChunk(meetingID: meeting.id, chunkIndex: 1, text: "Chunk 1")
    try db.write { dbConn in
        try chunk1.insert(dbConn)
        try chunk2.insert(dbConn)
    }

    var m1 = Mention(entityID: e1.id, meetingChunkID: chunk1.id, confidence: 0.9, extractionRunID: run.id)
    var m2 = Mention(entityID: e2.id, meetingChunkID: chunk2.id, confidence: 0.9, extractionRunID: run.id)
    try db.write { dbConn in
        try m1.insert(dbConn)
        try m2.insert(dbConn)
    }

    let strategy = CooccurrenceStrategy()
    let candidates = try await strategy.findCandidates(for: e1, in: [e1, e2], db: db)
    #expect(candidates.isEmpty)
}

@Test func cooccurrenceOrderIs4() {
    let strategy = CooccurrenceStrategy()
    #expect(strategy.order == 4)
    #expect(strategy.name == "cooccurrence")
}
