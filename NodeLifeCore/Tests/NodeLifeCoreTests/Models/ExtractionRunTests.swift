// ABOUTME: Tests for the ExtractionRun model record
// ABOUTME: Verifies GRDB conformance, default values, and extraction status enum

import Testing
import Foundation
@testable import NodeLifeCore

@Test func extractionRunCreationWithDefaults() {
    let run = ExtractionRun(meetingID: UUID(), model: "gpt-4", promptVersion: "v1")
    #expect(run.status == .running)
    #expect(run.completedAt == nil)
    #expect(run.errorMessage == nil)
    #expect(run.passName == nil)
    #expect(run.model == "gpt-4")
    #expect(run.promptVersion == "v1")
}

@Test func extractionRunTableName() {
    #expect(ExtractionRun.databaseTableName == "extraction_runs")
}

@Test func extractionStatusRawValues() {
    #expect(ExtractionStatus.running.rawValue == "running")
    #expect(ExtractionStatus.completed.rawValue == "completed")
    #expect(ExtractionStatus.failed.rawValue == "failed")
    #expect(ExtractionStatus.allCases.count == 3)
}
