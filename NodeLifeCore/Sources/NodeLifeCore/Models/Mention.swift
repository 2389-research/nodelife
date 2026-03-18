// ABOUTME: Mention record linking an Entity to a specific MeetingChunk where it was found
// ABOUTME: Tracks extraction confidence and the ExtractionRun that produced the mention

import Foundation
import GRDB

public struct Mention: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var entityID: UUID
    public var meetingChunkID: UUID
    public var confidence: Double
    public var extractionRunID: UUID

    public init(
        id: UUID = UUID(),
        entityID: UUID,
        meetingChunkID: UUID,
        confidence: Double,
        extractionRunID: UUID
    ) {
        self.id = id
        self.entityID = entityID
        self.meetingChunkID = meetingChunkID
        self.confidence = confidence
        self.extractionRunID = extractionRunID
    }
}

extension Mention: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "mentions"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let entityID = Column(CodingKeys.entityID)
        public static let meetingChunkID = Column(CodingKeys.meetingChunkID)
        public static let confidence = Column(CodingKeys.confidence)
        public static let extractionRunID = Column(CodingKeys.extractionRunID)
    }

    public static let entity = belongsTo(Entity.self)
    public static let meetingChunk = belongsTo(MeetingChunk.self)
    public static let extractionRun = belongsTo(ExtractionRun.self)
}
