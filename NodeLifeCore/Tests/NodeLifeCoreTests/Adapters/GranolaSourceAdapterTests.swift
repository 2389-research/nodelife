// ABOUTME: Tests for GranolaSourceAdapter verifying meeting listing, error handling, and fixture parsing
// ABOUTME: Uses temporary directories with fixture JSON files to validate adapter behavior

import Testing
import Foundation
@testable import NodeLifeCore

@Test func granolaAdapterMetadata() {
    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: "/tmp/test-granola"))
    #expect(adapter.metadata.id == "granola")
    #expect(adapter.metadata.name == "Granola Source Adapter")
    #expect(adapter.metadata.version == "1.0.0")
}

@Test func granolaAdapterConformsToSourceAdapter() {
    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: "/tmp/test-granola"))
    let _: any SourceAdapter = adapter
    // Compiles means it conforms
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

@Test func granolaAdapterListsMeetingsFromFixtures() async throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Create fixture meeting JSON
    let meetingData: [String: Any] = [
        "id": "test-meeting-1",
        "title": "Sprint Planning",
        "date": ISO8601DateFormatter().string(from: Date()),
        "duration": 3600.0,
        "transcript": "Hello team, let's discuss the sprint goals."
    ]
    let jsonData = try JSONSerialization.data(withJSONObject: meetingData)
    try jsonData.write(to: tmpDir.appendingPathComponent("meeting_test-meeting-1.json"))

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(!meetings.isEmpty)
    #expect(meetings[0].title == "Sprint Planning")
    #expect(meetings[0].sourceID == "test-meeting-1")
    #expect(meetings[0].sourceAdapter == "granola")
    #expect(meetings[0].rawTranscript == "Hello team, let's discuss the sprint goals.")
}

@Test func granolaAdapterReturnsEmptyForEmptyDirectory() async throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(meetings.isEmpty)
}

@Test func granolaAdapterFiltersByDate() async throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Create a meeting with an old date
    let oldDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    let meetingData: [String: Any] = [
        "id": "old-meeting",
        "title": "Old Meeting",
        "date": ISO8601DateFormatter().string(from: oldDate),
        "duration": 1800.0,
        "transcript": "This is an old meeting."
    ]
    let jsonData = try JSONSerialization.data(withJSONObject: meetingData)
    try jsonData.write(to: tmpDir.appendingPathComponent("meeting_old.json"))

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))

    // Filter since yesterday should exclude the old meeting
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let meetings = try await adapter.listMeetings(since: yesterday)
    #expect(meetings.isEmpty)
}

@Test func granolaAdapterFetchMeetingThrowsForMissingID() async throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let adapter = GranolaSourceAdapter(config: GranolaConfig(dataPath: tmpDir.path))
    do {
        _ = try await adapter.fetchMeeting(id: "nonexistent")
        #expect(Bool(false), "Should have thrown")
    } catch {
        #expect(error is SourceAdapterError)
    }
}
