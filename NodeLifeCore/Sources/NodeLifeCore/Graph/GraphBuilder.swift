// ABOUTME: Actor that materializes graph projections from the GRDB database
// ABOUTME: Supports full, semantic, cooccurrence, bipartite, ego, and time-filtered projections

import Foundation
import GRDB

public actor GraphBuilder {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func build(projectionType: ProjectionType, filter: GraphFilter) throws -> GraphProjection {
        // Fetch entities and relationships from DB
        let (entities, relationships) = try database.read { db -> ([Entity], [Relationship]) in
            let entities = try Entity.fetchAll(db)
            let relationships = try Relationship.fetchAll(db)
            return (entities, relationships)
        }

        // Apply entity filter (including merged entity exclusion)
        let filteredEntities = entities.filter { filter.passesEntity($0) }

        // Build entity ID -> node mapping
        var entityToNode: [UUID: GraphNode] = [:]
        for entity in filteredEntities {
            let node = GraphNode(entityID: entity.id, label: entity.name, type: entity.kind)
            entityToNode[entity.id] = node
        }

        // Apply relationship filter
        var filteredRelationships = relationships.filter { filter.passesRelationship($0) }

        // Apply projection-type-specific filters
        switch projectionType {
        case .semantic:
            filteredRelationships = filteredRelationships.filter { $0.kind != .cooccurs }
        case .cooccurrence:
            filteredRelationships = filteredRelationships.filter { $0.kind == .cooccurs }
        case .bipartite(let leftTypes, let rightTypes):
            let leftSet = Set(leftTypes)
            let rightSet = Set(rightTypes)
            let entityKindByID = Dictionary(uniqueKeysWithValues: filteredEntities.map { ($0.id, $0.kind) })
            filteredRelationships = filteredRelationships.filter { rel in
                guard let srcKind = entityKindByID[rel.sourceEntityID],
                      let tgtKind = entityKindByID[rel.targetEntityID] else { return false }
                return (leftSet.contains(srcKind) && rightSet.contains(tgtKind)) ||
                       (rightSet.contains(srcKind) && leftSet.contains(tgtKind))
            }
        case .timeFiltered(let range):
            // Additional time filter on entities
            let timeFilteredEntityIDs = Set(filteredEntities.filter { range.contains($0.lastSeenAt) }.map { $0.id })
            entityToNode = entityToNode.filter { timeFilteredEntityIDs.contains($0.key) }
        case .full, .ego:
            break
        }

        // Build edges (only for entities that passed filter)
        let validEntityIDs = Set(entityToNode.keys)
        var edges: [GraphEdge] = []
        for rel in filteredRelationships {
            guard validEntityIDs.contains(rel.sourceEntityID),
                  validEntityIDs.contains(rel.targetEntityID),
                  let srcNode = entityToNode[rel.sourceEntityID],
                  let tgtNode = entityToNode[rel.targetEntityID] else { continue }
            let edge = GraphEdge(
                relationshipID: rel.id,
                sourceNodeID: srcNode.id,
                targetNodeID: tgtNode.id,
                type: rel.kind,
                weight: rel.weight
            )
            edges.append(edge)
        }

        var nodes = Array(entityToNode.values)

        // Handle ego projection (BFS from center)
        if case .ego(let entityID, let depth) = projectionType {
            let egoNodes = expandEgo(entityID: entityID, depth: depth, entityToNode: entityToNode, edges: edges)
            let egoNodeIDs = Set(egoNodes.map { $0.id })
            nodes = egoNodes
            edges = edges.filter { egoNodeIDs.contains($0.sourceNodeID) && egoNodeIDs.contains($0.targetNodeID) }
        }

        // Apply maxNodes limit (keep highest-degree nodes)
        if nodes.count > filter.maxNodes {
            var degreeCounts: [UUID: Int] = [:]
            for edge in edges {
                degreeCounts[edge.sourceNodeID, default: 0] += 1
                degreeCounts[edge.targetNodeID, default: 0] += 1
            }
            nodes.sort { (degreeCounts[$0.id] ?? 0) > (degreeCounts[$1.id] ?? 0) }
            let keepIDs = Set(nodes.prefix(filter.maxNodes).map { $0.id })
            nodes = nodes.filter { keepIDs.contains($0.id) }
            edges = edges.filter { keepIDs.contains($0.sourceNodeID) && keepIDs.contains($0.targetNodeID) }
        }

        return GraphProjection(nodes: nodes, edges: edges, projectionType: projectionType, filter: filter)
    }

    private func expandEgo(entityID: UUID, depth: Int, entityToNode: [UUID: GraphNode], edges: [GraphEdge]) -> [GraphNode] {
        // Find the node corresponding to the entity ID
        guard let centerNode = entityToNode[entityID] else { return [] }

        var visited: Set<UUID> = [centerNode.id]
        var frontier: Set<UUID> = [centerNode.id]

        for _ in 0..<depth {
            var nextFrontier: Set<UUID> = []
            for edge in edges {
                if frontier.contains(edge.sourceNodeID) && !visited.contains(edge.targetNodeID) {
                    nextFrontier.insert(edge.targetNodeID)
                }
                if frontier.contains(edge.targetNodeID) && !visited.contains(edge.sourceNodeID) {
                    nextFrontier.insert(edge.sourceNodeID)
                }
            }
            visited.formUnion(nextFrontier)
            frontier = nextFrontier
        }

        return entityToNode.values.filter { visited.contains($0.id) }
    }
}
