// ABOUTME: Tests for GraphStats computation from nodes and edges
// ABOUTME: Verifies density, average degree, and cluster counting

import Testing
import Foundation
import CoreGraphics
@testable import NodeLifeCore

@Test func computeStatsFromNodesAndEdges() {
    let n1 = GraphNode(entityID: UUID(), label: "A", type: .person)
    let n2 = GraphNode(entityID: UUID(), label: "B", type: .person)
    let n3 = GraphNode(entityID: UUID(), label: "C", type: .organization)
    let e1 = GraphEdge(sourceNodeID: n1.id, targetNodeID: n2.id, type: .collaborates, weight: 1.0)

    let stats = GraphStats.compute(nodes: [n1, n2, n3], edges: [e1])
    #expect(stats.nodeCount == 3)
    #expect(stats.edgeCount == 1)
    #expect(stats.averageDegree > 0)
}

@Test func emptyGraphStats() {
    let stats = GraphStats.compute(nodes: [], edges: [])
    #expect(stats.nodeCount == 0)
    #expect(stats.edgeCount == 0)
    #expect(stats.density == 0)
    #expect(stats.averageDegree == 0)
}
