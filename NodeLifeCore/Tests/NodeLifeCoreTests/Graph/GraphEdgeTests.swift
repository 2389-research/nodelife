// ABOUTME: Tests for GraphEdge immutable value type
// ABOUTME: Verifies construction, weight updates, and evidence tracking

import Testing
import Foundation
@testable import NodeLifeCore

@Test func graphEdgeCreation() {
    let src = UUID()
    let tgt = UUID()
    let edge = GraphEdge(sourceNodeID: src, targetNodeID: tgt, type: .worksFor, weight: 0.8)
    #expect(edge.sourceNodeID == src)
    #expect(edge.targetNodeID == tgt)
    #expect(edge.type == .worksFor)
    #expect(edge.weight == 0.8)
    #expect(edge.evidenceCount == 0)
}

@Test func graphEdgeWithWeight() {
    let edge = GraphEdge(sourceNodeID: UUID(), targetNodeID: UUID(), type: .collaborates, weight: 0.5)
    let updated = edge.withWeight(0.9)
    #expect(updated.weight == 0.9)
}

@Test func graphEdgeWithEvidence() {
    let edge = GraphEdge(sourceNodeID: UUID(), targetNodeID: UUID(), type: .mentions, weight: 1.0)
    let updated = edge.withAdditionalEvidence(3)
    #expect(updated.evidenceCount == 3)
}
