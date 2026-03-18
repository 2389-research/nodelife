// ABOUTME: MergeHistory record tracking entity merge, split, and undo operations
// ABOUTME: Preserves original entity data for auditing and potential rollback

import Foundation
import GRDB

public enum MergeAction: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case merge
    case split
    case undo
}

public struct MergeHistory: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var primaryEntityId: UUID
    public var mergedEntityId: UUID
    public var action: MergeAction
    public var reason: String?
    public var originalEntityData: String
    public var originalAliasesData: String?
    public var originalRelationshipsData: String?
    public var performedAt: Date
    public var undoneAt: Date?

    public init(
        id: UUID = UUID(),
        primaryEntityId: UUID,
        mergedEntityId: UUID,
        action: MergeAction,
        reason: String? = nil,
        originalEntityData: String,
        originalAliasesData: String? = nil,
        originalRelationshipsData: String? = nil,
        performedAt: Date = Date(),
        undoneAt: Date? = nil
    ) {
        self.id = id
        self.primaryEntityId = primaryEntityId
        self.mergedEntityId = mergedEntityId
        self.action = action
        self.reason = reason
        self.originalEntityData = originalEntityData
        self.originalAliasesData = originalAliasesData
        self.originalRelationshipsData = originalRelationshipsData
        self.performedAt = performedAt
        self.undoneAt = undoneAt
    }
}

extension MergeHistory: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "merge_history"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let primaryEntityId = Column(CodingKeys.primaryEntityId)
        public static let mergedEntityId = Column(CodingKeys.mergedEntityId)
        public static let action = Column(CodingKeys.action)
        public static let reason = Column(CodingKeys.reason)
        public static let originalEntityData = Column(CodingKeys.originalEntityData)
        public static let originalAliasesData = Column(CodingKeys.originalAliasesData)
        public static let originalRelationshipsData = Column(CodingKeys.originalRelationshipsData)
        public static let performedAt = Column(CodingKeys.performedAt)
        public static let undoneAt = Column(CodingKeys.undoneAt)
    }
}
