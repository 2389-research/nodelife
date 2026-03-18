// ABOUTME: Meeting record representing a single ingested meeting transcript
// ABOUTME: Uses UUID primary key with GRDB persistence to the meetings table

import Foundation
import GRDB

public enum TranscriptStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case pending
    case cached
    case chunked
    case normalized
    case extracted
    case failed
}

public struct Meeting: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sourceID: String
    public var title: String
    public var date: Date
    public var duration: TimeInterval
    public var rawTranscript: String
    public var normalizedTranscript: String?
    public var summary: String?
    public var sourceAdapter: String
    public var transcriptStatus: TranscriptStatus
    public var importedAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        sourceID: String,
        title: String,
        date: Date,
        duration: TimeInterval,
        rawTranscript: String,
        normalizedTranscript: String? = nil,
        summary: String? = nil,
        sourceAdapter: String,
        transcriptStatus: TranscriptStatus = .pending,
        importedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.date = date
        self.duration = duration
        self.rawTranscript = rawTranscript
        self.normalizedTranscript = normalizedTranscript
        self.summary = summary
        self.sourceAdapter = sourceAdapter
        self.transcriptStatus = transcriptStatus
        self.importedAt = importedAt
        self.updatedAt = updatedAt
    }
}

extension Meeting: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "meetings"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let sourceID = Column(CodingKeys.sourceID)
        public static let title = Column(CodingKeys.title)
        public static let date = Column(CodingKeys.date)
        public static let duration = Column(CodingKeys.duration)
        public static let rawTranscript = Column(CodingKeys.rawTranscript)
        public static let normalizedTranscript = Column(CodingKeys.normalizedTranscript)
        public static let summary = Column(CodingKeys.summary)
        public static let sourceAdapter = Column(CodingKeys.sourceAdapter)
        public static let transcriptStatus = Column(CodingKeys.transcriptStatus)
        public static let importedAt = Column(CodingKeys.importedAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }

    public static let chunks = hasMany(MeetingChunk.self)
}
