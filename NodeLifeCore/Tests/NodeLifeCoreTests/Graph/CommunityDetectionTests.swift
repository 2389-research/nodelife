// ABOUTME: Tests for label propagation community detection
// ABOUTME: Verifies cluster assignment for cliques, disconnected components, and edge cases

import Testing
import Foundation
import CoreGraphics
@testable import NodeLifeCore

@Test func twoCliquesConnectedByBridgeYieldsTwoCommunities() {
    let adjacency: [[Int]] = [
        [1, 2],       // 0
        [0, 2],       // 1
        [0, 1, 3],    // 2 (bridge)
        [2, 4, 5],    // 3 (bridge)
        [3, 5],       // 4
        [3, 4],       // 5
    ]
    let labels = CommunityDetection.labelPropagation(adjacency: adjacency, maxIterations: 10)
    #expect(labels[0] == labels[1])
    #expect(labels[1] == labels[2])
    #expect(labels[3] == labels[4])
    #expect(labels[4] == labels[5])
    #expect(labels[0] != labels[3])
}

@Test func disconnectedComponentsGetSeparateLabels() {
    let adjacency: [[Int]] = [
        [1],    // 0
        [0],    // 1
        [3],    // 2
        [2],    // 3
    ]
    let labels = CommunityDetection.labelPropagation(adjacency: adjacency, maxIterations: 10)
    #expect(labels[0] == labels[1])
    #expect(labels[2] == labels[3])
    #expect(labels[0] != labels[2])
}

@Test func singleNodeGraph() {
    let labels = CommunityDetection.labelPropagation(adjacency: [[]], maxIterations: 10)
    #expect(labels == [0])
}

@Test func completeGraphSingleCommunity() {
    let adjacency: [[Int]] = [
        [1, 2, 3],
        [0, 2, 3],
        [0, 1, 3],
        [0, 1, 2],
    ]
    let labels = CommunityDetection.labelPropagation(adjacency: adjacency, maxIterations: 10)
    let unique = Set(labels)
    #expect(unique.count == 1)
}

@Test func tieBreakingProducesDeterministicResults() {
    let adjacency: [[Int]] = [
        [1, 2],
        [0, 2],
        [0, 1, 3],
        [2, 4],
        [3],
    ]
    let labels1 = CommunityDetection.labelPropagation(adjacency: adjacency, maxIterations: 10)
    let labels2 = CommunityDetection.labelPropagation(adjacency: adjacency, maxIterations: 10)
    #expect(labels1 == labels2)
}

@Test func buildAdjacencyFromEdgeIndices() {
    let adjacency = CommunityDetection.buildAdjacency(
        nodeCount: 3,
        edgeIndices: [(0, 1), (1, 2)]
    )
    #expect(adjacency[0] == [1])
    #expect(adjacency[1] == [0, 2])
    #expect(adjacency[2] == [1])
}

@Test func emptyGraphReturnsEmpty() {
    let labels = CommunityDetection.labelPropagation(adjacency: [], maxIterations: 10)
    #expect(labels.isEmpty)
}
