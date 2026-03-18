// ABOUTME: Tests for the Meeting model record
// ABOUTME: Verifies GRDB conformance, default values, and transcript status lifecycle

import Testing
import Foundation
@testable import NodeLifeCore

@Test func meetingCreationSetsDefaults() {
    let meeting = Meeting(
        sourceID: "test-123",
        title: "Standup",
        date: Date(),
        duration: 3600,
        rawTranscript: "Hello world",
        sourceAdapter: "muesli"
    )

    #expect(meeting.id.uuidString.count == 36)
    #expect(meeting.transcriptStatus == .pending)
    #expect(meeting.summary == nil)
}

@Test func meetingTranscriptStatusRawValues() {
    #expect(TranscriptStatus.pending.rawValue == "pending")
    #expect(TranscriptStatus.cached.rawValue == "cached")
    #expect(TranscriptStatus.chunked.rawValue == "chunked")
    #expect(TranscriptStatus.normalized.rawValue == "normalized")
    #expect(TranscriptStatus.extracted.rawValue == "extracted")
    #expect(TranscriptStatus.failed.rawValue == "failed")
}

@Test func meetingTableName() {
    #expect(Meeting.databaseTableName == "meetings")
}
