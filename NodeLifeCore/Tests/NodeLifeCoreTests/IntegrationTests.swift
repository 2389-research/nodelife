// ABOUTME: Integration tests verifying model CRUD operations against a real in-memory database
// ABOUTME: Tests insert, fetch, update, and delete for all 9 model types

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

// MARK: - Helper

/// Creates a Meeting and inserts it, returning the inserted record.
/// Many models require a meeting to exist due to foreign key constraints.
private func insertMeeting(in db: Database, sourceID: String = "test-src") throws -> Meeting {
    var meeting = Meeting(
        sourceID: sourceID,
        title: "Test Meeting",
        date: Date(),
        duration: 3600,
        rawTranscript: "Hello world",
        sourceAdapter: "test"
    )
    try meeting.insert(db)
    return meeting
}

/// Creates an ExtractionRun linked to a meeting and inserts it.
private func insertExtractionRun(in db: Database, meetingID: UUID) throws -> ExtractionRun {
    var run = ExtractionRun(meetingID: meetingID, model: "test-model", promptVersion: "v1")
    try run.insert(db)
    return run
}

// MARK: - Meeting Tests

@Test func meetingRoundTrip() throws {
    let db = try AppDatabase.makeInMemory()
    var meeting = Meeting(
        sourceID: "test-1",
        title: "Test Meeting",
        date: Date(),
        duration: 3600,
        rawTranscript: "Hello",
        sourceAdapter: "muesli"
    )

    try db.write { dbConn in
        try meeting.insert(dbConn)
    }

    let fetched = try db.read { dbConn in
        try Meeting.fetchOne(dbConn, key: meeting.id)
    }

    #expect(fetched != nil)
    #expect(fetched?.title == "Test Meeting")
    #expect(fetched?.transcriptStatus == .pending)
}

@Test func meetingUpdate() throws {
    let db = try AppDatabase.makeInMemory()
    var meeting = Meeting(
        sourceID: "upd-1",
        title: "Before",
        date: Date(),
        duration: 60,
        rawTranscript: "raw",
        sourceAdapter: "test"
    )

    try db.write { dbConn in
        try meeting.insert(dbConn)
        meeting.title = "After"
        meeting.transcriptStatus = .normalized
        try meeting.update(dbConn)
    }

    let fetched = try db.read { dbConn in
        try Meeting.fetchOne(dbConn, key: meeting.id)
    }

    #expect(fetched?.title == "After")
    #expect(fetched?.transcriptStatus == .normalized)
}

@Test func meetingDelete() throws {
    let db = try AppDatabase.makeInMemory()
    var meeting = Meeting(
        sourceID: "del-1",
        title: "Doomed",
        date: Date(),
        duration: 60,
        rawTranscript: "bye",
        sourceAdapter: "test"
    )

    try db.write { dbConn in
        try meeting.insert(dbConn)
        _ = try meeting.delete(dbConn)
    }

    let fetched = try db.read { dbConn in
        try Meeting.fetchOne(dbConn, key: meeting.id)
    }

    #expect(fetched == nil)
}

// MARK: - Entity Tests

@Test func entityWithMergedIntoId() throws {
    let db = try AppDatabase.makeInMemory()
    var primary = Entity(name: "Harper Reed", kind: .person)
    var duplicate = Entity(name: "Harper", kind: .person)

    try db.write { dbConn in
        try primary.insert(dbConn)
        try duplicate.insert(dbConn)
        duplicate.mergedIntoId = primary.id
        try duplicate.update(dbConn)
    }

    let fetched = try db.read { dbConn in
        try Entity.fetchOne(dbConn, key: duplicate.id)
    }

    #expect(fetched?.mergedIntoId == primary.id)
}

@Test func entityCanonicalNameIsLowercased() throws {
    let db = try AppDatabase.makeInMemory()
    var entity = Entity(name: "ACME Corp", kind: .organization)

    try db.write { dbConn in
        try entity.insert(dbConn)
    }

    let fetched = try db.read { dbConn in
        try Entity.fetchOne(dbConn, key: entity.id)
    }

    #expect(fetched?.canonicalName == "acme corp")
}

// MARK: - MergeHistory Tests

@Test func mergeHistoryRoundTrip() throws {
    let db = try AppDatabase.makeInMemory()
    var history = MergeHistory(
        primaryEntityId: UUID(),
        mergedEntityId: UUID(),
        action: .merge,
        reason: "ExactMatchStrategy",
        originalEntityData: "{\"name\":\"test\"}"
    )

    try db.write { dbConn in
        try history.insert(dbConn)
    }

    let fetched = try db.read { dbConn in
        try MergeHistory.fetchOne(dbConn, key: history.id)
    }

    #expect(fetched != nil)
    #expect(fetched?.action == .merge)
    #expect(fetched?.undoneAt == nil)
}

@Test func mergeHistoryUndoUpdate() throws {
    let db = try AppDatabase.makeInMemory()
    var history = MergeHistory(
        primaryEntityId: UUID(),
        mergedEntityId: UUID(),
        action: .merge,
        reason: "test",
        originalEntityData: "{}"
    )

    try db.write { dbConn in
        try history.insert(dbConn)
        history.undoneAt = Date()
        try history.update(dbConn)
    }

    let fetched = try db.read { dbConn in
        try MergeHistory.fetchOne(dbConn, key: history.id)
    }

    #expect(fetched?.undoneAt != nil)
}

// MARK: - Relationship Tests

@Test func relationshipUsesWeightNotStrength() throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        let meeting = try insertMeeting(in: dbConn, sourceID: "rel-src")
        let run = try insertExtractionRun(in: dbConn, meetingID: meeting.id)

        var entity1 = Entity(name: "A", kind: .person)
        var entity2 = Entity(name: "B", kind: .organization)
        try entity1.insert(dbConn)
        try entity2.insert(dbConn)

        var rel = Relationship(
            sourceEntityID: entity1.id,
            targetEntityID: entity2.id,
            kind: .worksFor,
            weight: 0.85,
            extractionRunID: run.id
        )
        try rel.insert(dbConn)

        let fetched = try Relationship.fetchOne(dbConn, key: rel.id)
        #expect(fetched?.weight == 0.85)
        #expect(fetched?.confidence == 0.0)
    }
}

@Test func relationshipDelete() throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        let meeting = try insertMeeting(in: dbConn, sourceID: "rel-del")
        let run = try insertExtractionRun(in: dbConn, meetingID: meeting.id)

        var entity1 = Entity(name: "X", kind: .person)
        var entity2 = Entity(name: "Y", kind: .person)
        try entity1.insert(dbConn)
        try entity2.insert(dbConn)

        var rel = Relationship(
            sourceEntityID: entity1.id,
            targetEntityID: entity2.id,
            kind: .collaborates,
            weight: 1.0,
            extractionRunID: run.id
        )
        try rel.insert(dbConn)
        _ = try rel.delete(dbConn)

        let fetched = try Relationship.fetchOne(dbConn, key: rel.id)
        #expect(fetched == nil)
    }
}

// MARK: - Cascade Delete Tests

@Test func foreignKeysCascadeDeleteMeetingChunks() throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        let meeting = try insertMeeting(in: dbConn, sourceID: "fk-test")

        var chunk = MeetingChunk(meetingID: meeting.id, chunkIndex: 0, text: "hello")
        try chunk.insert(dbConn)

        // Delete meeting — chunk should cascade
        let meetingCopy = meeting
        _ = try meetingCopy.delete(dbConn)

        let chunkCount = try MeetingChunk
            .filter(MeetingChunk.Columns.meetingID == meeting.id)
            .fetchCount(dbConn)
        #expect(chunkCount == 0)
    }
}

@Test func foreignKeysCascadeDeleteEntityAliases() throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var entity = Entity(name: "Test", kind: .person)
        try entity.insert(dbConn)

        var alias = EntityAlias(entityID: entity.id, alias: "Tester", source: .auto)
        try alias.insert(dbConn)

        _ = try entity.delete(dbConn)

        let aliasCount = try EntityAlias
            .filter(EntityAlias.Columns.entityID == entity.id)
            .fetchCount(dbConn)
        #expect(aliasCount == 0)
    }
}

// MARK: - MeetingChunk Tests

@Test func meetingChunkRoundTrip() throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        let meeting = try insertMeeting(in: dbConn, sourceID: "chunk-src")

        var chunk = MeetingChunk(
            meetingID: meeting.id,
            chunkIndex: 0,
            text: "first segment",
            speaker: "Harper"
        )
        try chunk.insert(dbConn)

        let fetched = try MeetingChunk.fetchOne(dbConn, key: chunk.id)
        #expect(fetched?.text == "first segment")
        #expect(fetched?.speaker == "Harper")
        #expect(fetched?.chunkIndex == 0)
    }
}

// MARK: - Mention Tests

@Test func mentionRoundTrip() throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        let meeting = try insertMeeting(in: dbConn, sourceID: "m-1")
        let run = try insertExtractionRun(in: dbConn, meetingID: meeting.id)

        var chunk = MeetingChunk(meetingID: meeting.id, chunkIndex: 0, text: "test")
        try chunk.insert(dbConn)

        var entity = Entity(name: "Test Entity", kind: .concept)
        try entity.insert(dbConn)

        var mention = Mention(
            entityID: entity.id,
            meetingChunkID: chunk.id,
            confidence: 0.95,
            extractionRunID: run.id
        )
        try mention.insert(dbConn)

        let fetched = try Mention.fetchOne(dbConn, key: mention.id)
        #expect(fetched?.confidence == 0.95)
        #expect(fetched?.entityID == entity.id)
    }
}

// MARK: - Job Tests

@Test func jobRoundTrip() throws {
    let db = try AppDatabase.makeInMemory()
    var job = Job(kind: "extraction", payload: "{}".data(using: .utf8)!)

    try db.write { dbConn in
        try job.insert(dbConn)
    }

    let fetched = try db.read { dbConn in
        try Job.fetchOne(dbConn, key: job.id)
    }

    #expect(fetched != nil)
    #expect(fetched?.status == .pending)
    #expect(fetched?.attempts == 0)
}

@Test func jobStatusUpdate() throws {
    let db = try AppDatabase.makeInMemory()
    var job = Job(kind: "normalize", payload: Data())

    try db.write { dbConn in
        try job.insert(dbConn)
        job.status = .running
        job.attempts = 1
        job.startedAt = Date()
        try job.update(dbConn)
    }

    let fetched = try db.read { dbConn in
        try Job.fetchOne(dbConn, key: job.id)
    }

    #expect(fetched?.status == .running)
    #expect(fetched?.attempts == 1)
    #expect(fetched?.startedAt != nil)
}

// MARK: - EntityAlias Tests

@Test func entityAliasRoundTrip() throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var entity = Entity(name: "Harper Reed", kind: .person)
        try entity.insert(dbConn)

        var alias = EntityAlias(entityID: entity.id, alias: "Harp Dog", source: .manual)
        try alias.insert(dbConn)

        let fetched = try EntityAlias.fetchOne(dbConn, key: alias.id)
        #expect(fetched?.alias == "Harp Dog")
        #expect(fetched?.source == .manual)
    }
}

// MARK: - ExtractionRun Tests

@Test func extractionRunRoundTrip() throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        let meeting = try insertMeeting(in: dbConn, sourceID: "er-1")

        var run = ExtractionRun(
            meetingID: meeting.id,
            model: "claude-opus-4-6",
            promptVersion: "v2",
            passName: "entities"
        )
        try run.insert(dbConn)

        let fetched = try ExtractionRun.fetchOne(dbConn, key: run.id)
        #expect(fetched?.model == "claude-opus-4-6")
        #expect(fetched?.status == .running)
        #expect(fetched?.passName == "entities")
    }
}

@Test func extractionRunStatusUpdate() throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        let meeting = try insertMeeting(in: dbConn, sourceID: "er-upd")

        var run = ExtractionRun(meetingID: meeting.id, model: "gpt-4", promptVersion: "v1")
        try run.insert(dbConn)

        run.status = .completed
        run.completedAt = Date()
        try run.update(dbConn)

        let fetched = try ExtractionRun.fetchOne(dbConn, key: run.id)
        #expect(fetched?.status == .completed)
        #expect(fetched?.completedAt != nil)
    }
}

// MARK: - End-to-End Integration Tests

@Test func endToEndSyncAndSearch() async throws {
    let db = try AppDatabase.makeInMemory()

    // Create a meeting with chunks directly
    try db.write { dbConn in
        var meeting = Meeting(
            sourceID: "e2e-1",
            title: "Product Roadmap Discussion",
            date: Date(),
            duration: 3600,
            rawTranscript: "Harper discussed the product roadmap with the team",
            sourceAdapter: "test"
        )
        meeting.transcriptStatus = .cached
        try meeting.insert(dbConn)

        var chunk = MeetingChunk(meetingID: meeting.id, chunkIndex: 0, text: "Harper discussed the product roadmap")
        try chunk.insert(dbConn)
    }

    // Search should find the meeting
    let searchService = SearchService(database: db)
    let results = try await searchService.search(query: "roadmap")
    #expect(!results.isEmpty)
}

@Test func jobQueueRoundTrip() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let job = try await queue.enqueue(kind: "test", payload: "{}".data(using: .utf8)!)
    let claimed = try await queue.claim(kinds: ["test"])

    #expect(claimed != nil)
    #expect(claimed?.id == job.id)

    try await queue.complete(jobID: job.id)

    // Verify completed
    let completed = try db.read { db in
        try Job.fetchOne(db, key: job.id)
    }
    #expect(completed?.status == .completed)
}

@Test func syncServiceImportsAndSearchFinds() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    // Create a mock adapter with test data
    let meetingID = UUID()
    let meeting = Meeting(
        id: meetingID,
        sourceID: "e2e-sync-1",
        title: "Engineering Sprint Review",
        date: Date(),
        duration: 1800,
        rawTranscript: "The team discussed velocity improvements",
        sourceAdapter: "mock"
    )
    let chunks = [
        MeetingChunk(meetingID: meetingID, chunkIndex: 0, text: "The team discussed velocity improvements and sprint goals"),
        MeetingChunk(meetingID: meetingID, chunkIndex: 1, text: "Action items were assigned for the next iteration"),
    ]

    // Use a simple inline adapter
    struct E2EAdapter: SourceAdapter {
        var metadata: AdapterMetadata { AdapterMetadata(id: "mock", name: "E2E Mock", version: "1.0") }
        let testMeetings: [Meeting]
        let testChunks: [UUID: [MeetingChunk]]

        func listMeetings(since: Date?) async throws -> [Meeting] { testMeetings }
        func fetchMeeting(id: String) async throws -> Meeting {
            guard let m = testMeetings.first(where: { $0.sourceID == id }) else {
                throw SourceAdapterError.meetingNotFound(id)
            }
            return m
        }
        func fetchTranscript(meetingID: UUID) async throws -> [MeetingChunk] {
            testChunks[meetingID] ?? []
        }
    }

    let adapter = E2EAdapter(testMeetings: [meeting], testChunks: [meetingID: chunks])
    let syncService = SyncService(database: db, sourceAdapter: adapter, jobQueue: queue)

    // Run sync
    for await _ in syncService.sync() {}

    // Verify meeting was stored
    let storedMeetings = try db.read { db in try Meeting.fetchAll(db) }
    #expect(storedMeetings.count == 1)
    #expect(storedMeetings.first?.title == "Engineering Sprint Review")

    // Verify chunks were stored
    let storedChunks = try db.read { db in try MeetingChunk.fetchAll(db) }
    #expect(storedChunks.count == 2)

    // Verify search finds the content
    let searchService = SearchService(database: db)
    let results = try await searchService.search(query: "velocity")
    #expect(!results.isEmpty)

    // Verify extraction job was enqueued
    let jobs = try db.read { db in try Job.fetchAll(db) }
    #expect(jobs.count == 1)
    #expect(jobs.first?.kind == "extraction")
}
