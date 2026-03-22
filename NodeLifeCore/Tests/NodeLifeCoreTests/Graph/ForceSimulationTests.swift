// ABOUTME: Tests for the 5-force graph simulation engine
// ABOUTME: Verifies convergence, pinning, sleep/wake, and edge cases

import Testing
import Foundation
import CoreGraphics
@testable import NodeLifeCore

private func makeProjection(
    nodeCount: Int,
    edges: [(Int, Int)] = []
) -> (GraphProjection, [GraphNode]) {
    var nodes: [GraphNode] = []
    for i in 0..<nodeCount {
        nodes.append(GraphNode(
            entityID: UUID(),
            label: "Node\(i)",
            type: .person,
            position: CGPoint(
                x: Double.random(in: -100...100),
                y: Double.random(in: -100...100)
            )
        ))
    }
    var graphEdges: [GraphEdge] = []
    for (src, tgt) in edges {
        graphEdges.append(GraphEdge(
            sourceNodeID: nodes[src].id,
            targetNodeID: nodes[tgt].id,
            type: .collaborates,
            weight: 1.0
        ))
    }
    let projection = GraphProjection(
        nodes: nodes, edges: graphEdges, projectionType: .full
    )
    return (projection, nodes)
}

@Test @MainActor func kineticEnergyDecreasesOverTime() async {
    let (projection, _) = makeProjection(nodeCount: 10, edges: [(0,1),(1,2),(2,3)])
    let sim = ForceSimulation()
    sim.load(projection: projection)
    sim.runBatch(iterations: 20)

    let energy1 = sim.kineticEnergy
    for _ in 0..<50 { sim.tick() }
    let energy2 = sim.kineticEnergy

    #expect(energy2 < energy1)
}

@Test @MainActor func pinnedNodesMaintainPosition() async {
    let (projection, _) = makeProjection(nodeCount: 3)
    let sim = ForceSimulation()
    sim.load(projection: projection)

    let pinnedIndex = 0
    let originalPos = sim.positions[pinnedIndex]
    sim.pin(index: pinnedIndex, at: originalPos)
    sim.runBatch(iterations: 50)

    #expect(sim.positions[pinnedIndex] == originalPos)
}

@Test @MainActor func simulationSleepsWhenEnergyLow() async {
    let (projection, _) = makeProjection(nodeCount: 3, edges: [(0,1)])
    let sim = ForceSimulation()
    sim.minimumAwakeSeconds = 0
    sim.load(projection: projection)
    sim.runBatch(iterations: 100)

    for _ in 0..<500 {
        if !sim.isRunning { break }
        sim.tick()
    }
    #expect(!sim.isRunning)
}

@Test @MainActor func wakeResumesSimulation() async {
    let (projection, _) = makeProjection(nodeCount: 3, edges: [(0,1)])
    let sim = ForceSimulation()
    sim.minimumAwakeSeconds = 0
    sim.load(projection: projection)
    sim.runBatch(iterations: 200)

    for _ in 0..<500 {
        if !sim.isRunning { break }
        sim.tick()
    }
    #expect(!sim.isRunning)

    sim.wake()
    #expect(sim.isRunning)
}

@Test @MainActor func minimumAwakeTimePreventsRapidSleepCycling() async {
    let (projection, _) = makeProjection(nodeCount: 2, edges: [(0,1)])
    let sim = ForceSimulation()
    sim.minimumAwakeSeconds = 10.0
    sim.load(projection: projection)
    sim.runBatch(iterations: 200)

    for _ in 0..<100 { sim.tick() }
    #expect(sim.isRunning)
}

@Test @MainActor func allForcesProduceFiniteValues() async {
    let nodes = [
        GraphNode(entityID: UUID(), label: "A", type: .person, position: CGPoint(x: 50, y: 50)),
        GraphNode(entityID: UUID(), label: "B", type: .person, position: CGPoint(x: 50, y: 50)),
    ]
    let edge = GraphEdge(sourceNodeID: nodes[0].id, targetNodeID: nodes[1].id, type: .collaborates, weight: 1.0)
    let projection = GraphProjection(nodes: nodes, edges: [edge], projectionType: .full)
    let sim = ForceSimulation()
    sim.load(projection: projection)
    sim.runBatch(iterations: 50)

    for pos in sim.positions {
        #expect(pos.x.isFinite)
        #expect(pos.y.isFinite)
    }
}

@Test @MainActor func zeroEdgeGraphProducesSpreadLayout() async {
    let (projection, _) = makeProjection(nodeCount: 5)
    let sim = ForceSimulation()
    sim.load(projection: projection)
    sim.runBatch(iterations: 100)

    for pos in sim.positions {
        #expect(pos.x.isFinite)
        #expect(pos.y.isFinite)
    }
    let dx = sim.positions[0].x - sim.positions[1].x
    let dy = sim.positions[0].y - sim.positions[1].y
    #expect(sqrt(dx * dx + dy * dy) > 5)
}

@Test @MainActor func singleNodePlacedNearCenter() async {
    let (projection, _) = makeProjection(nodeCount: 1)
    let sim = ForceSimulation()
    sim.load(projection: projection)
    sim.runBatch(iterations: 50)

    let pos = sim.positions[0]
    #expect(abs(pos.x) < 50)
    #expect(abs(pos.y) < 50)
}

@Test @MainActor func emptyGraphSkipsSimulation() async {
    let projection = GraphProjection(nodes: [], edges: [], projectionType: .full)
    let sim = ForceSimulation()
    sim.load(projection: projection)
    #expect(sim.positions.isEmpty)
    sim.runBatch(iterations: 50)
    #expect(sim.positions.isEmpty)
}
