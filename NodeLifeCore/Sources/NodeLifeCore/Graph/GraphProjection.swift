// ABOUTME: Immutable snapshot of a materialized graph with query methods
// ABOUTME: Contains nodes, edges, projection type, filter, and computed stats

import Foundation

public struct GraphProjection: Sendable, Codable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]
    public var projectionType: ProjectionType
    public var filter: GraphFilter
    public var generatedAt: Date
    public var stats: GraphStats

    public init(
        nodes: [GraphNode],
        edges: [GraphEdge],
        projectionType: ProjectionType,
        filter: GraphFilter = .default,
        generatedAt: Date = Date()
    ) {
        self.nodes = nodes
        self.edges = edges
        self.projectionType = projectionType
        self.filter = filter
        self.generatedAt = generatedAt
        self.stats = GraphStats.compute(nodes: nodes, edges: edges)
    }

    public func node(forEntity entityID: UUID) -> GraphNode? {
        nodes.first { $0.entityID == entityID }
    }

    public func edges(forNode nodeID: UUID) -> [GraphEdge] {
        edges.filter { $0.sourceNodeID == nodeID || $0.targetNodeID == nodeID }
    }

    public func neighbors(ofNode nodeID: UUID) -> [GraphNode] {
        let connectedIDs = edges(forNode: nodeID).flatMap { edge in
            [edge.sourceNodeID, edge.targetNodeID]
        }
        let neighborIDs = Set(connectedIDs).subtracting([nodeID])
        return nodes.filter { neighborIDs.contains($0.id) }
    }

    public func subgraph(nodeIDs: Set<UUID>) -> GraphProjection {
        let filteredNodes = nodes.filter { nodeIDs.contains($0.id) }
        let filteredEdges = edges.filter { nodeIDs.contains($0.sourceNodeID) && nodeIDs.contains($0.targetNodeID) }
        return GraphProjection(nodes: filteredNodes, edges: filteredEdges, projectionType: projectionType, filter: filter)
    }
}
