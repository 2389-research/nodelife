// ABOUTME: Tests for MuesliCacheAdapter verifying meeting listing, error handling, and fixture parsing
// ABOUTME: Uses temporary directories with fixture JSON metadata files to validate adapter behavior

import Testing
import Foundation
@testable import NodeLifeCore

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
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Create fixture metadata JSON
    let metadataData: [String: Any] = [
        "id": "muesli-cache",
        "title": "Daily Standup",
        "date": ISO8601DateFormatter().string(from: Date()),
        "duration": 900.0
    ]
    let jsonData = try JSONSerialization.data(withJSONObject: metadataData)
    try jsonData.write(to: tmpDir.appendingPathComponent("standup_metadata.json"))

    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(!meetings.isEmpty)
    #expect(meetings[0].title == "Daily Standup")
    #expect(meetings[0].sourceID == "standup")
    #expect(meetings[0].sourceAdapter == "muesli-cache")
}

@Test func muesliAdapterReturnsEmptyForEmptyDirectory() async throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: tmpDir.path))
    let meetings = try await adapter.listMeetings(since: nil)
    #expect(meetings.isEmpty)
}

@Test func muesliAdapterFiltersByDate() async throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Create a meeting with an old date
    let oldDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    let metadataData: [String: Any] = [
        "id": "muesli-cache",
        "title": "Old Standup",
        "date": ISO8601DateFormatter().string(from: oldDate),
        "duration": 600.0
    ]
    let jsonData = try JSONSerialization.data(withJSONObject: metadataData)
    try jsonData.write(to: tmpDir.appendingPathComponent("old_standup_metadata.json"))

    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: tmpDir.path))

    // Filter since yesterday should exclude the old meeting
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let meetings = try await adapter.listMeetings(since: yesterday)
    #expect(meetings.isEmpty)
}

@Test func muesliAdapterFetchMeetingThrowsForMissingID() async throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let adapter = MuesliCacheAdapter(config: MuesliCacheConfig(cachePath: tmpDir.path))
    do {
        _ = try await adapter.fetchMeeting(id: "nonexistent")
        #expect(Bool(false), "Should have thrown")
    } catch {
        #expect(error is SourceAdapterError)
    }
}
