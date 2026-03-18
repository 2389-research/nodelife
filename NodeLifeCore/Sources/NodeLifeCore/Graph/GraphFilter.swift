// ABOUTME: Filter criteria for graph projections with entity and relationship predicates
// ABOUTME: Supports type filtering, weight thresholds, confidence minimums, and time ranges

import Foundation

public enum ProjectionType: Sendable, Codable, Hashable {
    case full
    case semantic
    case cooccurrence
    case bipartite(leftTypes: [EntityKind], rightTypes: [EntityKind])
    case ego(entityID: UUID, depth: Int)
    case timeFiltered(range: DateInterval)

    public var description: String {
        switch self {
        case .full: return "Full Graph"
        case .semantic: return "Semantic"
        case .cooccurrence: return "Co-occurrence"
        case .bipartite: return "Bipartite"
        case .ego: return "Ego Network"
        case .timeFiltered: return "Time Filtered"
        }
    }
}

public struct GraphFilter: Sendable, Codable, Hashable {
    public var entityTypes: Set<EntityKind>
    public var relationshipTypes: Set<RelationshipKind>
    public var minEdgeWeight: Double
    public var minConfidence: Double
    public var timeRange: DateInterval?
    public var maxNodes: Int

    public init(
        entityTypes: Set<EntityKind> = Set(EntityKind.allCases),
        relationshipTypes: Set<RelationshipKind> = Set(RelationshipKind.allCases),
        minEdgeWeight: Double = 0.0,
        minConfidence: Double = 0.0,
        timeRange: DateInterval? = nil,
        maxNodes: Int = 500
    ) {
        self.entityTypes = entityTypes
        self.relationshipTypes = relationshipTypes
        self.minEdgeWeight = minEdgeWeight
        self.minConfidence = minConfidence
        self.timeRange = timeRange
        self.maxNodes = maxNodes
    }

    public static let `default` = GraphFilter()

    public func passesEntity(_ entity: Entity) -> Bool {
        guard entityTypes.contains(entity.kind) else { return false }
        if entity.mergedIntoId != nil { return false }
        if let range = timeRange {
            guard range.contains(entity.lastSeenAt) else { return false }
        }
        return true
    }

    public func passesRelationship(_ relationship: Relationship) -> Bool {
        guard relationshipTypes.contains(relationship.kind) else { return false }
        guard relationship.weight >= minEdgeWeight else { return false }
        guard relationship.confidence >= minConfidence else { return false }
        return true
    }
}
