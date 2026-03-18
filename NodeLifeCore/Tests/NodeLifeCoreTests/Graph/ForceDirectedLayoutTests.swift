// ABOUTME: Tests for ForceDirectedLayout physics simulation
// ABOUTME: Verifies node separation, connected node attraction, and pinned node stability

import Testing
import Foundation
import CoreGraphics
@testable import NodeLifeCore

@Test func layoutSeparatesOverlappingNodes() async {
    let n1 = GraphNode(entityID: UUID(), label: "A", type: .person, position: .zero)
    let n2 = GraphNode(entityID: UUID(), label: "B", type: .person, position: CGPoint(x: 1, y: 1))

    let layout = ForceDirectedLayout(iterations: 50)
    let positioned = await layout.layout(nodes: [n1, n2], edges: [], bounds: CGSize(width: 800, height: 600))

    let dist = hypot(positioned[0].position.x - positioned[1].position.x,
                     positioned[0].position.y - positioned[1].position.y)
    #expect(dist > 10) // nodes should be pushed apart
}

@Test func layoutKeepsPinnedNodesFixed() async {
    let pinned = GraphNode(entityID: UUID(), label: "Pinned", type: .person, position: CGPoint(x: 100, y: 100), isPinned: true)
    let free = GraphNode(entityID: UUID(), label: "Free", type: .person, position: CGPoint(x: 101, y: 101))

    let layout = ForceDirectedLayout(iterations: 50)
    let positioned = await layout.layout(nodes: [pinned, free], edges: [], bounds: CGSize(width: 800, height: 600))

    let pinnedResult = positioned.first { $0.label == "Pinned" }!
    #expect(pinnedResult.position == CGPoint(x: 100, y: 100))
}

@Test func layoutAttractsConnectedNodes() async {
    let n1 = GraphNode(entityID: UUID(), label: "A", type: .person, position: CGPoint(x: 0, y: 0))
    let n2 = GraphNode(entityID: UUID(), label: "B", type: .person, position: CGPoint(x: 700, y: 500))
    let edge = GraphEdge(sourceNodeID: n1.id, targetNodeID: n2.id, type: .collaborates, weight: 2.0)

    let layout = ForceDirectedLayout(iterations: 100, attractionStrength: 0.05)
    let positioned = await layout.layout(nodes: [n1, n2], edges: [edge], bounds: CGSize(width: 800, height: 600))

    let dist = hypot(positioned[0].position.x - positioned[1].position.x,
                     positioned[0].position.y - positioned[1].position.y)
    let originalDist = hypot(CGFloat(700), CGFloat(500))
    #expect(dist < originalDist) // connected nodes should be closer
}

@Test func layoutReturnsEmptyForEmptyInput() async {
    let layout = ForceDirectedLayout()
    let result = await layout.layout(nodes: [], edges: [], bounds: CGSize(width: 800, height: 600))
    #expect(result.isEmpty)
}
