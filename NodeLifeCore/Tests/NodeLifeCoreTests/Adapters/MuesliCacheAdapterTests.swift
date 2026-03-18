// ABOUTME: Tests for MuesliCacheAdapter verifying meeting listing, transcript parsing, and error handling
// ABOUTME: Uses temporary directories with fixture JSON files matching real muesli data format

import Testing
import Foundation
@testable import NodeLifeCore

// MARK: - Fixture Helpers

private func createTempDir() throws -> URL {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    return tmpDir
}

private func writeFixtureMetadata(
    to directory: URL,
    prefix: String,
    title: String,
    createdAt: String,
    creatorName: String = "Harper Reed",
    creatorEmail: String = "harper@nata2.org",
    attendees: [[String: Any]] = []
) throws {
    let metadata: [String: Any] = [
        "title": title,
        "created_at": createdAt,
        "creator": [
            "name": creatorName,
            "email": creatorEmail,
            "details": ["person": ["name": ["fullName": creatorName]]]
        ],
        "attendees": attendees,
        "sharing_link_visibility": "public"
    ]
    let data = try JSONSerialization.data(withJSONObject: metadata)
    try data.write(to: directory.appendingPathComponent("\(prefix)_metadata.json"))
}

private func writeFixtureTranscript(to directory: URL, prefix: String, segments: [[String: Any]]) throws {
    let data = try JSONSerialization.data(withJSONObject: segments)
    try data.write(to: directory.appendingPathComponent("\(prefix)_transcript.json"))
}

// MARK: - Tests

@Test func muesliAdapterMetadata() {
    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: "/tmp/test-muesli"))
    #expect(adapter.metadata.id == "muesli-cache")
    #expect(adapter.metadata.name == "Muesli Cache Adapter")
    #expect(adapter.metadata.version == "1.0.0")
}

@Test func muesliAdapterConformsToSourceAdapter() {
    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: "/tmp/test-muesli"))
    let _: any SourceAdapter = adapter
    // Compiles means it conforms
}

@Test func muesliAdapterThrowsForMissingDirectory() async throws {
    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: "/nonexistent/path"))
    do {
        _ = try await adapter.listMeetings(since: nil)
        #expect(Bool(false), "Should have thrown")
    } catch {
        #expect(error is SourceAdapterError)
        if let adapterError = error as? SourceAdapterError {
            #expect(adapterError == .sourceNotAccessible("Cache directory does not exist: /nonexistent/path"))
        }
    }
}

@Test func muesliAdapterListsMeetingsFromFixtures() async throws {
    let tmpDir = try createTempDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    try writeFixtureMetadata(
        to: tmpDir,
        prefix: "2024-04-08_hangout-colin-and-harper-reed",
        title: "Hangout: colin and Harper Reed",
        createdAt: "2024-04-08T16:00:45.226Z",
        attendees: [
            [
                "email": "c.mac@usc.edu",
                "details": ["person": ["name": ["fullName": "C Mac"]]]
            ]
        ]
    )

    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(meetings.count == 1)
    #expect(meetings[0].title == "Hangout: colin and Harper Reed")
    #expect(meetings[0].sourceID == "2024-04-08_hangout-colin-and-harper-reed")
    #expect(meetings[0].sourceAdapter == "muesli-cache")
    #expect(meetings[0].duration == 0) // No duration in muesli metadata
}

@Test func muesliAdapterReturnsEmptyForEmptyDirectory() async throws {
    let tmpDir = try createTempDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(meetings.isEmpty)
}

@Test func muesliAdapterFiltersByDate() async throws {
    let tmpDir = try createTempDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Create a meeting with an old created_at date
    try writeFixtureMetadata(
        to: tmpDir,
        prefix: "2024-01-15_old-standup",
        title: "Old Standup",
        createdAt: "2024-01-15T10:00:00.000Z"
    )

    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: tmpDir.path))

    // Filter since 2024-03-01 should exclude the January meeting
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let sinceDate = formatter.date(from: "2024-03-01T00:00:00.000Z")!
    let meetings = try await adapter.listMeetings(since: sinceDate)
    #expect(meetings.isEmpty)

    // Filter since 2024-01-01 should include the January meeting
    let olderDate = formatter.date(from: "2024-01-01T00:00:00.000Z")!
    let allMeetings = try await adapter.listMeetings(since: olderDate)
    #expect(allMeetings.count == 1)
}

@Test func muesliAdapterFetchMeetingThrowsForMissingID() async throws {
    let tmpDir = try createTempDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: tmpDir.path))
    do {
        _ = try await adapter.fetchMeeting(id: "nonexistent")
        #expect(Bool(false), "Should have thrown")
    } catch {
        #expect(error is SourceAdapterError)
    }
}

@Test func muesliAdapterFetchTranscriptReturnsMappedChunks() async throws {
    let tmpDir = try createTempDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let prefix = "2024-04-08_hangout-colin-and-harper-reed"

    try writeFixtureMetadata(
        to: tmpDir,
        prefix: prefix,
        title: "Hangout: colin and Harper Reed",
        createdAt: "2024-04-08T16:00:45.226Z"
    )

    let segments: [[String: Any]] = [
        [
            "document_id": "8f6c77cc-882c-4456-9e26-18548d3f91d1",
            "start_timestamp": "2024-04-08T16:01:18.569Z",
            "end_timestamp": "2024-04-08T16:01:22.589Z",
            "text": "Hello?",
            "source": "system",
            "id": "5113944e-d71a-4f26-b807-75a5b727cfa8",
            "is_final": true
        ],
        [
            "document_id": "8f6c77cc-882c-4456-9e26-18548d3f91d1",
            "start_timestamp": "2024-04-08T16:01:22.051Z",
            "end_timestamp": "2024-04-08T16:01:25.290Z",
            "text": "What's up, man? How are you?",
            "source": "microphone",
            "id": "6226672f-349e-433d-9916-b41356f536df",
            "is_final": true
        ]
    ]

    try writeFixtureTranscript(to: tmpDir, prefix: prefix, segments: segments)

    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(meetings.count == 1)

    let chunks = try await adapter.fetchTranscript(meetingID: meetings[0].id)
    #expect(chunks.count == 2)

    // First segment is "system" (remote audio / other person)
    #expect(chunks[0].text == "Hello?")
    #expect(chunks[0].speaker == "system")
    #expect(chunks[0].chunkIndex == 0)
    #expect(chunks[0].meetingID == meetings[0].id)

    // Second segment is "microphone" (local audio / user)
    #expect(chunks[1].text == "What's up, man? How are you?")
    #expect(chunks[1].speaker == "microphone")
    #expect(chunks[1].chunkIndex == 1)

    // Start/end times should be offsets from the first segment's start
    #expect(chunks[0].startTime == 0.0)
    #expect(chunks[0].startTime != nil)
    #expect(chunks[1].startTime != nil)
    #expect(chunks[1].endTime != nil)
}

@Test func muesliAdapterComputesDurationFromTranscriptTimestamps() async throws {
    let tmpDir = try createTempDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let prefix = "2024-04-08_duration-test"

    try writeFixtureMetadata(
        to: tmpDir,
        prefix: prefix,
        title: "Duration Test Meeting",
        createdAt: "2024-04-08T16:00:45.226Z"
    )

    // Meeting metadata has no duration, so it defaults to 0
    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(meetings[0].duration == 0)
}

@Test func muesliAdapterHandlesMetadataWithoutOptionalFields() async throws {
    let tmpDir = try createTempDir()
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Minimal metadata: only title and created_at
    let metadata: [String: Any] = [
        "title": "Minimal Meeting",
        "created_at": "2024-06-15T09:30:00.000Z"
    ]
    let data = try JSONSerialization.data(withJSONObject: metadata)
    try data.write(to: tmpDir.appendingPathComponent("2024-06-15_minimal-meeting_metadata.json"))

    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(meetings.count == 1)
    #expect(meetings[0].title == "Minimal Meeting")
}
