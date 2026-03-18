// ABOUTME: EntityAlias record representing an alternative name for an Entity
// ABOUTME: Tracks auto-detected and manually assigned aliases with source tracking

import Foundation
import GRDB

public enum AliasSource: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case auto
    case manual
}

public struct EntityAlias: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var entityID: UUID
    public var alias: String
    public var source: AliasSource

    public init(
        id: UUID = UUID(),
        entityID: UUID,
        alias: String,
        source: AliasSource
    ) {
        self.id = id
        self.entityID = entityID
        self.alias = alias
        self.source = source
    }
}

extension EntityAlias: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "entity_aliases"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let entityID = Column(CodingKeys.entityID)
        public static let alias = Column(CodingKeys.alias)
        public static let source = Column(CodingKeys.source)
    }

    public static let entity = belongsTo(Entity.self)
}
