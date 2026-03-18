// ABOUTME: Tests for DataSourceDetector filesystem scanning
// ABOUTME: Uses temporary directories to verify Granola and Muesli detection

import Testing
import Foundation
@testable import NodeLifeCore

@Test func detectGranolaFindsJsonFiles() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    for i in 0..<3 {
        let data = "{}".data(using: .utf8)!
        try data.write(to: tmpDir.appendingPathComponent("meeting_\(i).json"))
    }

    let detector = DataSourceDetector()
    let result = detector.detectGranola(at: tmpDir.path)

    #expect(result.found == true)
    #expect(result.meetingCount == 3)
    #expect(result.path == tmpDir.path)
}

@Test func detectGranolaReturnsFalseForMissingDirectory() {
    let detector = DataSourceDetector()
    let result = detector.detectGranola(at: "/nonexistent/path/\(UUID().uuidString)")

    #expect(result.found == false)
    #expect(result.meetingCount == 0)
}

@Test func detectGranolaExcludesNonJsonFiles() throws {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    try "{}".data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("meeting_1.json"))
    try "text".data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("config.txt"))
    try "{}".data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("settings.plist"))

    let detector = DataSourceDetector()
    let result = detector.detectGranola(at: tmpDir.path)

    #expect(result.found == true)
    #expect(result.meetingCount == 1)
}

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

@Test func detectAllSourcesReturnsResultsForBoth() throws {
    let granolaDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let muesliDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: granolaDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: muesliDir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: granolaDir)
        try? FileManager.default.removeItem(at: muesliDir)
    }

    try "{}".data(using: .utf8)!.write(to: granolaDir.appendingPathComponent("meeting_1.json"))
    try "{}".data(using: .utf8)!.write(to: muesliDir.appendingPathComponent("m1_metadata.json"))

    let detector = DataSourceDetector()
    let results = detector.detectAll(granolaPath: granolaDir.path, muesliPath: muesliDir.path)

    #expect(results.granola.found == true)
    #expect(results.granola.meetingCount == 1)
    #expect(results.muesli.found == true)
    #expect(results.muesli.meetingCount == 1)
}
