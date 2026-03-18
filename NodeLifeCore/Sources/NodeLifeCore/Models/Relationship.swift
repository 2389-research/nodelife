// ABOUTME: Relationship record representing a typed edge between two entities in the knowledge graph
// ABOUTME: Supports 12 relationship kinds with confidence scoring and evidence tracking

import Foundation
import GRDB

public enum RelationshipKind: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case worksFor
    case worksOn
    case manages
    case collaborates
    case mentions
    case cooccurs
    case discusses
    case relatesTo
    case owns
    case inspiredBy
    case partOf
    case reports
}

public struct Relationship: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sourceEntityID: UUID
    public var targetEntityID: UUID
    public var kind: RelationshipKind
    public var weight: Double
    public var confidence: Double
    public var evidence: String?
    public var evidenceChunkRefsJson: String?
    public var extractionRunID: UUID

    public init(
        id: UUID = UUID(),
        sourceEntityID: UUID,
        targetEntityID: UUID,
        kind: RelationshipKind,
        weight: Double,
        confidence: Double = 0.0,
        evidence: String? = nil,
        evidenceChunkRefsJson: String? = nil,
        extractionRunID: UUID
    ) {
        self.id = id
        self.sourceEntityID = sourceEntityID
        self.targetEntityID = targetEntityID
        self.kind = kind
        self.weight = weight
        self.confidence = confidence
        self.evidence = evidence
        self.evidenceChunkRefsJson = evidenceChunkRefsJson
        self.extractionRunID = extractionRunID
    }
}

extension Relationship: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "relationships"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let sourceEntityID = Column(CodingKeys.sourceEntityID)
        public static let targetEntityID = Column(CodingKeys.targetEntityID)
        public static let kind = Column(CodingKeys.kind)
        public static let weight = Column(CodingKeys.weight)
        public static let confidence = Column(CodingKeys.confidence)
        public static let evidence = Column(CodingKeys.evidence)
        public static let evidenceChunkRefsJson = Column(CodingKeys.evidenceChunkRefsJson)
        public static let extractionRunID = Column(CodingKeys.extractionRunID)
    }

    public static let sourceEntity = belongsTo(Entity.self, using: ForeignKey(["sourceEntityID"]))
    public static let targetEntity = belongsTo(Entity.self, using: ForeignKey(["targetEntityID"]))
    public static let extractionRun = belongsTo(ExtractionRun.self)
}
