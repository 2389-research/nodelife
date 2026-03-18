// ABOUTME: Cleans raw MeetingChunk text by collapsing whitespace and trimming
// ABOUTME: Writes normalizedText on each chunk and advances meeting transcriptStatus to .normalized

import Foundation
import GRDB

public enum TranscriptNormalizer {
    public static func normalize(meetingId: UUID, in db: Database) throws {
        guard var meeting = try Meeting.fetchOne(db, key: meetingId),
              meeting.transcriptStatus == .chunked else {
            return
        }

        let chunks = try MeetingChunk
            .filter(MeetingChunk.Columns.meetingID == meetingId)
            .order(MeetingChunk.Columns.chunkIndex.asc)
            .fetchAll(db)

        for var chunk in chunks {
            chunk.normalizedText = cleanText(chunk.text)
            try chunk.update(db)
        }

        meeting.transcriptStatus = .normalized
        try meeting.update(db)
    }

    public static func cleanText(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
