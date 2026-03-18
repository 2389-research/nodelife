// ABOUTME: Tests for DataSourceDetector filesystem scanning
// ABOUTME: Uses temporary directories to verify Granola and Muesli detection

import Testing
import Foundation
@testable import NodeLifeCore

// MARK: - Granola Tests

@Test func detectGranolaFindsCacheFile() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let cacheJSON = makeCacheJSON(documents: [
        makeDocument(id: "uuid-1", type: "meeting", title: "Meeting 1"),
        makeDocument(id: "uuid-2", type: "meeting", title: "Meeting 2"),
    ])
    try cacheJSON.write(to: tmpDir.appendingPathComponent("cache-v6.json"), atomically: true, encoding: .utf8)

    let detector = DataSourceDetector()
    let result = detector.detectGranola(at: tmpDir.path)

    #expect(result.found == true)
    #expect(result.meetingCount == 2)
    #expect(result.path == tmpDir.path)
}

@Test func detectGranolaCountsOnlyMeetingDocuments() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let cacheJSON = makeCacheJSON(documents: [
        makeDocument(id: "uuid-1", type: "meeting", title: "Meeting 1"),
        makeDocument(id: "uuid-2", type: "meeting", title: "Meeting 2"),
        makeDocument(id: "uuid-3", type: "note", title: "A Note"),
        makeDocument(id: "uuid-4", type: "meeting", title: "Deleted Meeting", deletedAt: "2026-01-05T00:00:00Z"),
    ])
    try cacheJSON.write(to: tmpDir.appendingPathComponent("cache-v6.json"), atomically: true, encoding: .utf8)

    let detector = DataSourceDetector()
    let result = detector.detectGranola(at: tmpDir.path)

    #expect(result.found == true)
    #expect(result.meetingCount == 2)
}

@Test func detectGranolaReturnsFalseForMissingDirectory() {
    let detector = DataSourceDetector()
    let result = detector.detectGranola(at: "/nonexistent/path/\(UUID().uuidString)")

    #expect(result.found == false)
    #expect(result.meetingCount == 0)
}

@Test func detectGranolaReturnsFalseForMissingCacheFile() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Directory exists but no cache-v6.json
    try "hello".data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("something.txt"))

    let detector = DataSourceDetector()
    let result = detector.detectGranola(at: tmpDir.path)

    #expect(result.found == false)
    #expect(result.meetingCount == 0)
    #expect(result.path == tmpDir.path)
}

// MARK: - Muesli Tests

@Test func detectMuesliFindsMetadataFiles() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    for i in 0..<5 {
        try "{}".data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("meeting\(i)_metadata.json"))
    }
    try "{}".data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("cache.json"))

    let detector = DataSourceDetector()
    let result = detector.detectMuesli(at: tmpDir.path)

    #expect(result.found == true)
    #expect(result.meetingCount == 5)
}

@Test func detectMuesliReturnsFalseForMissingDirectory() {
    let detector = DataSourceDetector()
    let result = detector.detectMuesli(at: "/nonexistent/path/\(UUID().uuidString)")

    #expect(result.found == false)
    #expect(result.meetingCount == 0)
}

// MARK: - Combined Tests

@Test func detectAllSourcesReturnsResultsForBoth() throws {
    let granolaDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let muesliDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: granolaDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: muesliDir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: granolaDir)
        try? FileManager.default.removeItem(at: muesliDir)
    }

    let cacheJSON = makeCacheJSON(documents: [
        makeDocument(id: "uuid-1", type: "meeting", title: "Meeting 1"),
    ])
    try cacheJSON.write(to: granolaDir.appendingPathComponent("cache-v6.json"), atomically: true, encoding: .utf8)
    try "{}".data(using: .utf8)!.write(to: muesliDir.appendingPathComponent("m1_metadata.json"))

    let detector = DataSourceDetector()
    let results = detector.detectAll(granolaPath: granolaDir.path, muesliPath: muesliDir.path)

    #expect(results.granola.found == true)
    #expect(results.granola.meetingCount == 1)
    #expect(results.muesli.found == true)
    #expect(results.muesli.meetingCount == 1)
}

// MARK: - Test Helpers

private func makeDocument(id: String, type: String, title: String, deletedAt: String? = nil) -> String {
    let deletedValue = deletedAt.map { "\"\($0)\"" } ?? "null"
    return """
    "\(id)": { "id": "\(id)", "type": "\(type)", "title": "\(title)", "created_at": "2026-01-01T00:00:00Z", "deleted_at": \(deletedValue) }
    """
}

private func makeCacheJSON(documents: [String]) -> String {
    let docs = documents.joined(separator: ",\n        ")
    return """
    {
      "cache": {
        "state": {
          "documents": {
            \(docs)
          },
          "transcripts": {},
          "meetingsMetadata": {}
        }
      }
    }
    """
}
