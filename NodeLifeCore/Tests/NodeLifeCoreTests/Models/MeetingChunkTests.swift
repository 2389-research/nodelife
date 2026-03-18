// ABOUTME: Tests for the MeetingChunk model record
// ABOUTME: Verifies GRDB conformance, optional fields, and normalizedText field

import Testing
import Foundation
@testable import NodeLifeCore

@Test func meetingChunkCreationSetsDefaults() {
    let chunk = MeetingChunk(
        meetingID: UUID(),
        chunkIndex: 0,
        text: "Hello world"
    )

    #expect(chunk.normalizedText == nil)
    #expect(chunk.embeddingJson == nil)
    #expect(chunk.speaker == nil)
    #expect(chunk.startTime == nil)
}

@Test func meetingChunkTableName() {
    #expect(MeetingChunk.databaseTableName == "meeting_chunks")
}
