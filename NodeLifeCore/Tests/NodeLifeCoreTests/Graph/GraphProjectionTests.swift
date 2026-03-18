// ABOUTME: Tests for GraphProjection container and query methods
// ABOUTME: Verifies node lookup, edge queries, neighbor discovery, and subgraph extraction

import Testing
import Foundation
import CoreGraphics
@testable import NodeLifeCore

@Test func projectionNodeForEntity() {
    let entityId = UUID()
    let node = GraphNode(entityID: entityId, label: "Test", type: .person)
    let projection = GraphProjection(nodes: [node], edges: [], projectionType: .full)
    #expect(projection.node(forEntity: entityId)?.label == "Test")
}

@Test func projectionEdgesForNode() {
    let n1 = GraphNode(entityID: UUID(), label: "A", type: .person)
    let n2 = GraphNode(entityID: UUID(), label: "B", type: .organization)
    let edge = GraphEdge(sourceNodeID: n1.id, targetNodeID: n2.id, type: .worksFor, weight: 1.0)
    let projection = GraphProjection(nodes: [n1, n2], edges: [edge], projectionType: .full)

    let edges = projection.edges(forNode: n1.id)
    #expect(edges.count == 1)
}

@Test func projectionNeighbors() {
    let n1 = GraphNode(entityID: UUID(), label: "A", type: .person)
    let n2 = GraphNode(entityID: UUID(), label: "B", type: .person)
    let n3 = GraphNode(entityID: UUID(), label: "C", type: .person)
    let e1 = GraphEdge(sourceNodeID: n1.id, targetNodeID: n2.id, type: .collaborates, weight: 1.0)
    let projection = GraphProjection(nodes: [n1, n2, n3], edges: [e1], projectionType: .full)

    let neighbors = projection.neighbors(ofNode: n1.id)
    #expect(neighbors.count == 1)
    #expect(neighbors[0].id == n2.id)
}

@Test func projectionSubgraph() {
    let n1 = GraphNode(entityID: UUID(), label: "A", type: .person)
    let n2 = GraphNode(entityID: UUID(), label: "B", type: .person)
    let n3 = GraphNode(entityID: UUID(), label: "C", type: .person)
    let e1 = GraphEdge(sourceNodeID: n1.id, targetNodeID: n2.id, type: .collaborates, weight: 1.0)
    let e2 = GraphEdge(sourceNodeID: n2.id, targetNodeID: n3.id, type: .collaborates, weight: 1.0)
    let projection = GraphProjection(nodes: [n1, n2, n3], edges: [e1, e2], projectionType: .full)

    let sub = projection.subgraph(nodeIDs: Set([n1.id, n2.id]))
    #expect(sub.nodes.count == 2)
    #expect(sub.edges.count == 1) // only e1, not e2
}

@Test func projectionComputesStats() {
    let n1 = GraphNode(entityID: UUID(), label: "A", type: .person)
    let n2 = GraphNode(entityID: UUID(), label: "B", type: .person)
    let edge = GraphEdge(sourceNodeID: n1.id, targetNodeID: n2.id, type: .collaborates, weight: 1.0)
    let projection = GraphProjection(nodes: [n1, n2], edges: [edge], projectionType: .full)
    #expect(projection.stats.nodeCount == 2)
    #expect(projection.stats.edgeCount == 1)
}
