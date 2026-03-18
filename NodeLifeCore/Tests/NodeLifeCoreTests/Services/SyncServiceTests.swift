// ABOUTME: Tests for the SyncService meeting import orchestration
// ABOUTME: Uses a mock SourceAdapter to verify import, deduplication, and chunk storage

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

// Test adapter that returns fixture data
struct MockSourceAdapter: SourceAdapter {
    var metadata: AdapterMetadata { AdapterMetadata(id: "mock", name: "Mock", version: "1.0") }
    var meetings: [Meeting]
    var chunks: [UUID: [MeetingChunk]]

    func listMeetings(since: Date?) async throws -> [Meeting] {
        if let since = since {
            return meetings.filter { $0.date > since }
        }
        return meetings
    }

    func fetchMeeting(id: String) async throws -> Meeting {
        guard let meeting = meetings.first(where: { $0.sourceID == id }) else {
            throw SourceAdapterError.meetingNotFound(id)
        }
        return meeting
    }

    func fetchTranscript(meetingID: UUID) async throws -> [MeetingChunk] {
        return chunks[meetingID] ?? []
    }
}

@Test func syncImportsNewMeetings() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let meetingID = UUID()
    let meeting = Meeting(
        id: meetingID,
        sourceID: "src-1",
        title: "Test",
        date: Date(),
        duration: 60,
        rawTranscript: "hello",
        sourceAdapter: "mock"
    )
    let chunk = MeetingChunk(meetingID: meetingID, chunkIndex: 0, text: "hello world")

    let adapter = MockSourceAdapter(meetings: [meeting], chunks: [meetingID: [chunk]])
    let service = SyncService(database: db, sourceAdapter: adapter, jobQueue: queue)

    var lastProgress: SyncProgress?
    for await progress in service.sync() {
        lastProgress = progress
    }

    #expect(lastProgress?.isComplete == true)

    // Verify meeting was stored
    let stored = try db.read { db in
        try Meeting.filter(Meeting.Columns.sourceID == "src-1").fetchOne(db)
    }
    #expect(stored != nil)
    #expect(stored?.title == "Test")
    #expect(stored?.transcriptStatus == .cached)
}

@Test func syncSkipsDuplicates() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let meetingID = UUID()
    let meeting = Meeting(
        id: meetingID,
        sourceID: "dup-1",
        title: "Existing",
        date: Date(),
        duration: 60,
        rawTranscript: "hello",
        sourceAdapter: "mock"
    )

    // Pre-insert the meeting
    try db.write { dbConn in
        var m = meeting
        try m.insert(dbConn)
    }

    let adapter = MockSourceAdapter(meetings: [meeting], chunks: [:])
    let service = SyncService(database: db, sourceAdapter: adapter, jobQueue: queue)

    for await _ in service.sync() {}

    // Should still be just 1 meeting
    let count = try db.read { db in
        try Meeting.fetchCount(db)
    }
    #expect(count == 1)
}

@Test func syncStoresChunks() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let meetingID = UUID()
    let meeting = Meeting(
        id: meetingID,
        sourceID: "chunk-test",
        title: "Chunks",
        date: Date(),
        duration: 60,
        rawTranscript: "hello",
        sourceAdapter: "mock"
    )
    let chunks = [
        MeetingChunk(meetingID: meetingID, chunkIndex: 0, text: "first chunk"),
        MeetingChunk(meetingID: meetingID, chunkIndex: 1, text: "second chunk"),
    ]

    let adapter = MockSourceAdapter(meetings: [meeting], chunks: [meetingID: chunks])
    let service = SyncService(database: db, sourceAdapter: adapter, jobQueue: queue)

    for await _ in service.sync() {}

    let storedChunks = try db.read { db in
        try MeetingChunk.fetchAll(db)
    }
    #expect(storedChunks.count == 2)
}

@Test func syncEnqueuesExtractionJob() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let meetingID = UUID()
    let meeting = Meeting(
        id: meetingID,
        sourceID: "job-test",
        title: "Job Test",
        date: Date(),
        duration: 60,
        rawTranscript: "hello",
        sourceAdapter: "mock"
    )

    let adapter = MockSourceAdapter(meetings: [meeting], chunks: [:])
    let service = SyncService(database: db, sourceAdapter: adapter, jobQueue: queue)

    for await _ in service.sync() {}

    // Verify an extraction job was enqueued
    let jobCount = try await queue.count(status: .pending)
    #expect(jobCount == 1)
}

@Test func syncReportsProgressCorrectly() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let meetings = (0..<3).map { i in
        Meeting(
            id: UUID(),
            sourceID: "progress-\(i)",
            title: "Meeting \(i)",
            date: Date(),
            duration: 60,
            rawTranscript: "text \(i)",
            sourceAdapter: "mock"
        )
    }

    let adapter = MockSourceAdapter(meetings: meetings, chunks: [:])
    let service = SyncService(database: db, sourceAdapter: adapter, jobQueue: queue)

    var progressUpdates: [SyncProgress] = []
    for await progress in service.sync() {
        progressUpdates.append(progress)
    }

    // Should have: listing + importing(0/3) + importing(1/3) + importing(2/3) + importing(3/3) + complete
    #expect(progressUpdates.count >= 3)
    #expect(progressUpdates.last?.isComplete == true)
    #expect(progressUpdates.last?.totalCount == 3)
}
