// ABOUTME: Tests for GranolaSourceAdapter verifying parsing of Granola cache-v6.json format
// ABOUTME: Uses temporary directories with fixture cache files to validate adapter behavior

import Testing
import Foundation
@testable import NodeLifeCore

// MARK: - Fixture Helpers

/// Builds a fixture cache-v6.json structure and writes it to the given directory
private func writeFixtureCache(
    to directory: URL,
    documents: [String: Any] = [:],
    transcripts: [String: Any] = [:],
    meetingsMetadata: [String: Any] = [:]
) throws {
    let cache: [String: Any] = [
        "cache": [
            "state": [
                "documents": documents,
                "transcripts": transcripts,
                "meetingsMetadata": meetingsMetadata
            ]
        ]
    ]
    let data = try JSONSerialization.data(withJSONObject: cache, options: [.sortedKeys])
    try data.write(to: directory.appendingPathComponent("cache-v6.json"))
}

/// Creates a fixture document dictionary matching the real Granola format
private func makeDocument(
    id: String,
    title: String,
    createdAt: String = "2026-03-10T16:30:35.691Z",
    updatedAt: String = "2026-03-10T17:05:52.692Z",
    type: String = "meeting",
    deletedAt: String? = nil,
    notesPlain: String? = "Some meeting notes",
    notesMarkdown: String? = nil,
    calendarStart: String? = nil,
    calendarEnd: String? = nil,
    summary: String? = nil
) -> [String: Any] {
    var doc: [String: Any] = [
        "id": id,
        "title": title,
        "created_at": createdAt,
        "updated_at": updatedAt,
        "type": type,
        "transcribe": true
    ]
    if let notesPlain = notesPlain {
        doc["notes_plain"] = notesPlain
    }
    if let notesMarkdown = notesMarkdown {
        doc["notes_markdown"] = notesMarkdown
    }
    if let deletedAt = deletedAt {
        doc["deleted_at"] = deletedAt
    }
    if let summary = summary {
        doc["summary"] = summary
    }
    doc["people"] = [
        "creator": ["name": "Test User", "email": "test@example.com"],
        "attendees": [] as [[String: Any]]
    ]
    if let calendarStart = calendarStart, let calendarEnd = calendarEnd {
        doc["google_calendar_event"] = [
            "start": ["dateTime": calendarStart],
            "end": ["dateTime": calendarEnd]
        ]
    }
    return doc
}

/// Creates a fixture transcript segment matching the real Granola format
private func makeTranscriptSegment(
    id: String = UUID().uuidString,
    documentId: String,
    startTimestamp: String,
    endTimestamp: String,
    text: String,
    source: String = "microphone"
) -> [String: Any] {
    return [
        "id": id,
        "document_id": documentId,
        "start_timestamp": startTimestamp,
        "end_timestamp": endTimestamp,
        "text": text,
        "source": source,
        "is_final": true
    ]
}

/// Creates a temporary directory for testing
private func makeTmpDir() throws -> URL {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    return tmpDir
}

// MARK: - Tests

@Test func granolaAdapterMetadata() {
    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: "/tmp/test-granola"))
    #expect(adapter.metadata.id == "granola")
    #expect(adapter.metadata.name == "Granola Source Adapter")
    #expect(adapter.metadata.version == "1.0.0")
}

@Test func granolaAdapterConformsToSourceAdapter() {
    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: "/tmp/test-granola"))
    let _: any SourceAdapter = adapter
}

@Test func granolaAdapterThrowsForMissingDirectory() async throws {
    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: "/nonexistent/path"))
    do {
        _ = try await adapter.listMeetings(since: nil)
        #expect(Bool(false), "Should have thrown")
    } catch {
        #expect(error is SourceAdapterError)
        if let adapterError = error as? SourceAdapterError {
            #expect(adapterError == .sourceNotAccessible("Granola data directory does not exist: /nonexistent/path"))
        }
    }
}

@Test func granolaAdapterListsMeetingsFromFixtureCache() async throws {
    let tmpDir = try makeTmpDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let doc1 = makeDocument(
        id: "aaa-bbb-ccc",
        title: "Sprint Planning",
        createdAt: "2026-03-10T16:30:35.691Z",
        notesPlain: "We discussed sprint goals.",
        calendarStart: "2026-03-10T11:30:00-05:00",
        calendarEnd: "2026-03-10T12:30:00-05:00"
    )
    let doc2 = makeDocument(
        id: "ddd-eee-fff",
        title: "Design Review",
        createdAt: "2026-03-11T10:00:00.000Z",
        notesPlain: "Reviewed mockups."
    )

    try writeFixtureCache(to: tmpDir, documents: [
        "aaa-bbb-ccc": doc1,
        "ddd-eee-fff": doc2
    ])

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)

    #expect(meetings.count == 2)

    // Should be sorted by date descending
    let titles = meetings.map(\.title)
    #expect(titles.contains("Sprint Planning"))
    #expect(titles.contains("Design Review"))

    // Verify fields of a meeting
    let sprint = meetings.first { $0.title == "Sprint Planning" }!
    #expect(sprint.sourceID == "aaa-bbb-ccc")
    #expect(sprint.sourceAdapter == "granola")
    #expect(sprint.rawTranscript == "We discussed sprint goals.")
    // Duration from calendar event: 1 hour = 3600 seconds
    #expect(sprint.duration == 3600.0)
}

@Test func granolaAdapterReturnsEmptyForCacheWithNoMeetings() async throws {
    let tmpDir = try makeTmpDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Write cache with a non-meeting document
    let noteDoc = makeDocument(
        id: "note-1",
        title: "My Note",
        type: "note"
    )
    try writeFixtureCache(to: tmpDir, documents: ["note-1": noteDoc])

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(meetings.isEmpty)
}

@Test func granolaAdapterExcludesDeletedMeetings() async throws {
    let tmpDir = try makeTmpDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let deletedDoc = makeDocument(
        id: "del-1",
        title: "Deleted Meeting",
        deletedAt: "2026-03-12T10:00:00.000Z"
    )
    let activeDoc = makeDocument(
        id: "active-1",
        title: "Active Meeting"
    )
    try writeFixtureCache(to: tmpDir, documents: [
        "del-1": deletedDoc,
        "active-1": activeDoc
    ])

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(meetings.count == 1)
    #expect(meetings[0].title == "Active Meeting")
}

@Test func granolaAdapterFiltersByDate() async throws {
    let tmpDir = try makeTmpDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let oldDoc = makeDocument(
        id: "old-1",
        title: "Old Meeting",
        createdAt: "2025-01-01T10:00:00.000Z"
    )
    let recentDoc = makeDocument(
        id: "recent-1",
        title: "Recent Meeting",
        createdAt: "2026-03-15T10:00:00.000Z"
    )
    try writeFixtureCache(to: tmpDir, documents: [
        "old-1": oldDoc,
        "recent-1": recentDoc
    ])

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))

    // Filter since 2026-03-01
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let sinceDate = formatter.date(from: "2026-03-01T00:00:00.000Z")!

    let meetings = try await adapter.listMeetings(since: sinceDate)
    #expect(meetings.count == 1)
    #expect(meetings[0].title == "Recent Meeting")
}

@Test func granolaAdapterFetchMeetingBySourceID() async throws {
    let tmpDir = try makeTmpDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let doc = makeDocument(id: "fetch-me", title: "Fetchable Meeting")
    try writeFixtureCache(to: tmpDir, documents: ["fetch-me": doc])

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))
    let meeting = try await adapter.fetchMeeting(id: "fetch-me")
    #expect(meeting.title == "Fetchable Meeting")
    #expect(meeting.sourceID == "fetch-me")
}

@Test func granolaAdapterFetchMeetingThrowsForMissingID() async throws {
    let tmpDir = try makeTmpDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    try writeFixtureCache(to: tmpDir)

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))
    do {
        _ = try await adapter.fetchMeeting(id: "nonexistent")
        #expect(Bool(false), "Should have thrown")
    } catch {
        #expect(error is SourceAdapterError)
    }
}

@Test func granolaAdapterFetchTranscriptReturnsChunks() async throws {
    let tmpDir = try makeTmpDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let docId = "transcript-doc-1"
    let doc = makeDocument(id: docId, title: "Meeting With Transcript")

    let segments: [[String: Any]] = [
        makeTranscriptSegment(
            documentId: docId,
            startTimestamp: "2026-03-16T18:30:00.000Z",
            endTimestamp: "2026-03-16T18:30:05.000Z",
            text: "Hello everyone",
            source: "microphone"
        ),
        makeTranscriptSegment(
            documentId: docId,
            startTimestamp: "2026-03-16T18:30:06.000Z",
            endTimestamp: "2026-03-16T18:30:10.000Z",
            text: "Hi there",
            source: "system"
        ),
        makeTranscriptSegment(
            documentId: docId,
            startTimestamp: "2026-03-16T18:30:11.000Z",
            endTimestamp: "2026-03-16T18:30:15.000Z",
            text: "Let's begin",
            source: "microphone"
        )
    ]

    try writeFixtureCache(
        to: tmpDir,
        documents: [docId: doc],
        transcripts: [docId: segments]
    )

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))

    // First list to get the meeting UUID
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(meetings.count == 1)
    let meetingID = meetings[0].id

    let chunks = try await adapter.fetchTranscript(meetingID: meetingID)
    #expect(chunks.count == 3)

    // Check chunk ordering
    #expect(chunks[0].chunkIndex == 0)
    #expect(chunks[1].chunkIndex == 1)
    #expect(chunks[2].chunkIndex == 2)

    // Check text
    #expect(chunks[0].text == "Hello everyone")
    #expect(chunks[1].text == "Hi there")
    #expect(chunks[2].text == "Let's begin")

    // Check speakers (source field)
    #expect(chunks[0].speaker == "microphone")
    #expect(chunks[1].speaker == "system")
    #expect(chunks[2].speaker == "microphone")

    // Check time offsets from first segment
    #expect(chunks[0].startTime == 0.0)
    #expect(chunks[1].startTime == 6.0)
    #expect(chunks[2].startTime == 11.0)
    #expect(chunks[0].endTime == 5.0)
    #expect(chunks[1].endTime == 10.0)
    #expect(chunks[2].endTime == 15.0)
}

@Test func granolaAdapterFetchTranscriptReturnsEmptyWhenNoSegments() async throws {
    let tmpDir = try makeTmpDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let docId = "no-transcript-doc"
    let doc = makeDocument(id: docId, title: "Meeting Without Transcript")
    try writeFixtureCache(to: tmpDir, documents: [docId: doc])

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    let meetingID = meetings[0].id

    let chunks = try await adapter.fetchTranscript(meetingID: meetingID)
    #expect(chunks.isEmpty)
}

@Test func granolaAdapterDurationIsZeroWithoutCalendarEvent() async throws {
    let tmpDir = try makeTmpDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let doc = makeDocument(
        id: "no-cal",
        title: "No Calendar Meeting"
        // No calendarStart/calendarEnd
    )
    try writeFixtureCache(to: tmpDir, documents: ["no-cal": doc])

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(meetings.count == 1)
    #expect(meetings[0].duration == 0)
}
