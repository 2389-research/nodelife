// ABOUTME: Entity record representing an extracted person, organization, concept, etc
// ABOUTME: Uses UUID primary key with 10 entity kinds and optional merge tracking

import Foundation
import GRDB

public enum EntityKind: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case person
    case organization
    case project
    case concept
    case topic
    case place
    case actionItem
    case blogIdea
    case idea
    case other
}

public struct Entity: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var canonicalName: String
    public var kind: EntityKind
    public var summary: String?
    public var mergedIntoId: UUID?
    public var mentionCount: Int
    public var firstSeenAt: Date
    public var lastSeenAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kind: EntityKind,
        summary: String? = nil,
        mergedIntoId: UUID? = nil,
        mentionCount: Int = 0,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.canonicalName = name.lowercased()
        self.kind = kind
        self.summary = summary
        self.mergedIntoId = mergedIntoId
        self.mentionCount = mentionCount
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }
}

extension Entity: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "entities"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let name = Column(CodingKeys.name)
        public static let canonicalName = Column(CodingKeys.canonicalName)
        public static let kind = Column(CodingKeys.kind)
        public static let summary = Column(CodingKeys.summary)
        public static let mergedIntoId = Column(CodingKeys.mergedIntoId)
        public static let mentionCount = Column(CodingKeys.mentionCount)
        public static let firstSeenAt = Column(CodingKeys.firstSeenAt)
        public static let lastSeenAt = Column(CodingKeys.lastSeenAt)
    }

    // TODO: uncomment after Task 3
    // public static let aliases = hasMany(EntityAlias.self)
    // public static let mentions = hasMany(Mention.self)
}
