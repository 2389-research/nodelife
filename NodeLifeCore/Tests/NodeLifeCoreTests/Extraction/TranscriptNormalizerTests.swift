// ABOUTME: Tests for TranscriptNormalizer text cleaning
// ABOUTME: Verifies whitespace collapsing, status transitions, and chunk processing

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func cleanTextCollapsesWhitespace() {
    let result = TranscriptNormalizer.cleanText("  hello   world  \n\n  foo  ")
    #expect(result == "hello world foo")
}

@Test func cleanTextTrimsEdges() {
    let result = TranscriptNormalizer.cleanText("  hello  ")
    #expect(result == "hello")
}

@Test func normalizeUpdatesChunksAndStatus() throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var meeting = Meeting(sourceID: "norm-1", title: "Test", date: Date(), duration: 60, rawTranscript: "t", sourceAdapter: "test")
        meeting.transcriptStatus = .chunked
        try meeting.insert(dbConn)

        var chunk = MeetingChunk(meetingID: meeting.id, chunkIndex: 0, text: "  hello   world  ")
        try chunk.insert(dbConn)

        try TranscriptNormalizer.normalize(meetingId: meeting.id, in: dbConn)

        let updatedChunk = try MeetingChunk.fetchOne(dbConn, key: chunk.id)
        #expect(updatedChunk?.normalizedText == "hello world")

        let updatedMeeting = try Meeting.fetchOne(dbConn, key: meeting.id)
        #expect(updatedMeeting?.transcriptStatus == .normalized)
    }
}

@Test func normalizeSkipsNonChunkedMeetings() throws {
    let db = try AppDatabase.makeInMemory()

    try db.write { dbConn in
        var meeting = Meeting(sourceID: "norm-2", title: "Test", date: Date(), duration: 60, rawTranscript: "t", sourceAdapter: "test")
        meeting.transcriptStatus = .cached
        try meeting.insert(dbConn)

        try TranscriptNormalizer.normalize(meetingId: meeting.id, in: dbConn)

        let m = try Meeting.fetchOne(dbConn, key: meeting.id)
        #expect(m?.transcriptStatus == .cached)
    }
}
