// ABOUTME: Immutable value type representing an edge in a graph projection
// ABOUTME: Maps to a Relationship with weight, evidence count, and direction

import Foundation

public struct GraphEdge: Identifiable, Sendable, Codable, Hashable {
    public var id: UUID
    public var relationshipID: UUID?
    public var sourceNodeID: UUID
    public var targetNodeID: UUID
    public var type: RelationshipKind
    public var weight: Double
    public var evidenceCount: Int
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        relationshipID: UUID? = nil,
        sourceNodeID: UUID,
        targetNodeID: UUID,
        type: RelationshipKind,
        weight: Double,
        evidenceCount: Int = 0,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.relationshipID = relationshipID
        self.sourceNodeID = sourceNodeID
        self.targetNodeID = targetNodeID
        self.type = type
        self.weight = weight
        self.evidenceCount = evidenceCount
        self.metadata = metadata
    }

    public func withWeight(_ newWeight: Double) -> GraphEdge {
        var copy = self
        copy.weight = newWeight
        return copy
    }

    public func withAdditionalEvidence(_ count: Int) -> GraphEdge {
        var copy = self
        copy.evidenceCount = count
        return copy
    }
}
