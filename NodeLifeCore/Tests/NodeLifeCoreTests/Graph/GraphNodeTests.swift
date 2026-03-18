// ABOUTME: Tests for GraphNode immutable value type
// ABOUTME: Verifies construction, position updates, and cluster assignment

import Testing
import Foundation
import CoreGraphics
@testable import NodeLifeCore

@Test func graphNodeCreation() {
    let entityId = UUID()
    let node = GraphNode(entityID: entityId, label: "Harper", type: .person)
    #expect(node.entityID == entityId)
    #expect(node.label == "Harper")
    #expect(node.type == .person)
    #expect(node.position == .zero)
    #expect(node.isPinned == false)
}

@Test func graphNodeWithPosition() {
    let node = GraphNode(entityID: UUID(), label: "Test", type: .concept)
    let moved = node.withPosition(CGPoint(x: 100, y: 200))
    #expect(moved.position == CGPoint(x: 100, y: 200))
    #expect(moved.label == "Test")
}

@Test func graphNodeWithCluster() {
    let node = GraphNode(entityID: UUID(), label: "Test", type: .organization)
    let clustered = node.withClusterID(42)
    #expect(clustered.clusterID == 42)
}
