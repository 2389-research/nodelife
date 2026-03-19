// ABOUTME: Tests for DataSourceDetector filesystem scanning
// ABOUTME: Uses temporary directories to verify Granola detection via supabase.json

import Testing
import Foundation
@testable import NodeLifeCore

// MARK: - Granola Tests

@Test func detectGranolaFindsSessionFile() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let sessionJSON = """
    {"workos_tokens": "{\\"access_token\\": \\"test_token\\"}", "session_id": "test"}
    """
    try sessionJSON.write(to: tmpDir.appendingPathComponent("supabase.json"), atomically: true, encoding: .utf8)

    let detector = DataSourceDetector()
    let result = detector.detectGranola(at: tmpDir.path)

    #expect(result.found == true)
    #expect(result.meetingCount == 0)
    #expect(result.path == tmpDir.path)
}

@Test func detectGranolaReturnsFalseForMissingDirectory() {
    let detector = DataSourceDetector()
    let result = detector.detectGranola(at: "/nonexistent/path/\(UUID().uuidString)")

    #expect(result.found == false)
    #expect(result.meetingCount == 0)
}

@Test func detectGranolaReturnsFalseForMissingSessionFile() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    // Directory exists but no supabase.json
    try "hello".data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("something.txt"))

    let detector = DataSourceDetector()
    let result = detector.detectGranola(at: tmpDir.path)

    #expect(result.found == false)
    #expect(result.meetingCount == 0)
    #expect(result.path == tmpDir.path)
}

// MARK: - Combined Tests

@Test func detectAllSourcesReturnsGranolaResult() throws {
    let granolaDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: granolaDir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: granolaDir)
    }

    let sessionJSON = """
    {"workos_tokens": "{\\"access_token\\": \\"test_token\\"}", "session_id": "test"}
    """
    try sessionJSON.write(to: granolaDir.appendingPathComponent("supabase.json"), atomically: true, encoding: .utf8)

    let detector = DataSourceDetector()
    let results = detector.detectAll(granolaPath: granolaDir.path)

    #expect(results.granola.found == true)
    #expect(results.granola.meetingCount == 0)
}
