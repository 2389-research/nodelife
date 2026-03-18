// ABOUTME: MeetingChunk record representing a segment of a meeting transcript
// ABOUTME: Uses UUID primary key, belongs to a Meeting via meetingID foreign key

import Foundation
import GRDB

public struct MeetingChunk: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var meetingID: UUID
    public var chunkIndex: Int
    public var text: String
    public var normalizedText: String?
    public var speaker: String?
    public var startTime: TimeInterval?
    public var endTime: TimeInterval?
    public var embeddingJson: String?

    public init(
        id: UUID = UUID(),
        meetingID: UUID,
        chunkIndex: Int,
        text: String,
        normalizedText: String? = nil,
        speaker: String? = nil,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        embeddingJson: String? = nil
    ) {
        self.id = id
        self.meetingID = meetingID
        self.chunkIndex = chunkIndex
        self.text = text
        self.normalizedText = normalizedText
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
        self.embeddingJson = embeddingJson
    }
}

extension MeetingChunk: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "meeting_chunks"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let meetingID = Column(CodingKeys.meetingID)
        public static let chunkIndex = Column(CodingKeys.chunkIndex)
        public static let text = Column(CodingKeys.text)
        public static let normalizedText = Column(CodingKeys.normalizedText)
        public static let speaker = Column(CodingKeys.speaker)
        public static let startTime = Column(CodingKeys.startTime)
        public static let endTime = Column(CodingKeys.endTime)
        public static let embeddingJson = Column(CodingKeys.embeddingJson)
    }

    public static let meeting = belongsTo(Meeting.self)
}
