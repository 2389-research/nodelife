# Graph Layout Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the O(n^2) batch-only force layout with a 5-force Barnes-Hut simulation that shows clusters, runs at 60fps, and supports interactive node dragging.

**Architecture:** Three new files in NodeLifeCore (QuadTree, CommunityDetection, ForceSimulation) replace ForceDirectedLayout. GraphViewModel owns the simulation lifecycle. GraphCanvasView switches to TimelineView-driven rendering with progressive reveal and split drag/pan gestures.

**Tech Stack:** Swift 6.0 strict concurrency, SwiftUI Canvas + TimelineView, @MainActor @Observable, Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-21-graph-layout-engine-design.md`

---

## File Structure

### New files (NodeLifeCore/Sources/NodeLifeCore/Graph/)

| File | Responsibility |
|------|---------------|
| `QuadTree.swift` | Barnes-Hut quadtree struct for O(n log n) repulsion approximation |
| `CommunityDetection.swift` | Label propagation algorithm assigning cluster IDs |
| `ForceSimulation.swift` | @MainActor @Observable class with 5 forces, two-phase lifecycle, sleep/wake |

### New test files (NodeLifeCore/Tests/NodeLifeCoreTests/Graph/)

| File | Responsibility |
|------|---------------|
| `QuadTreeTests.swift` | Insertion, subdivision, center-of-mass, force accuracy |
| `CommunityDetectionTests.swift` | Cluster assignment correctness |
| `ForceSimulationTests.swift` | Convergence, pinning, sleep/wake, edge cases |

### Modified files

| File | Changes |
|------|---------|
| `Sources/NodeLife/GraphViewModel.swift` | Replace `ForceDirectedLayout` with `ForceSimulation`, add simulation lifecycle, drag-to-pin |
| `Sources/NodeLife/Views/Graph/GraphCanvasView.swift` | TimelineView wrapper, read positions from simulation, progressive reveal, degree-based sizing, drag-vs-pan gesture split |

### Deleted files

| File | Reason |
|------|--------|
| `NodeLifeCore/Sources/NodeLifeCore/Graph/ForceDirectedLayout.swift` | Replaced by ForceSimulation |
| `NodeLifeCore/Tests/NodeLifeCoreTests/Graph/ForceDirectedLayoutTests.swift` | Replaced by ForceSimulationTests |

---

## Task 1: QuadTree

**Files:**
- Create: `NodeLifeCore/Sources/NodeLifeCore/Graph/QuadTree.swift`
- Test: `NodeLifeCore/Tests/NodeLifeCoreTests/Graph/QuadTreeTests.swift`

### Background

The quadtree is a spatial data structure that partitions 2D space into quadrants. For Barnes-Hut force approximation, each internal node stores the total mass (count of graph nodes) and center of mass for its quadrant. During force calculation, if a quadrant is "far enough away" (cell size / distance < theta), the entire quadrant is treated as a single point mass instead of iterating every node.

Key types:
- `QuadTree` is a struct (value type) with a bounding `CGRect`
- `QuadTreeNode` is an enum: `.empty`, `.leaf(index: Int, position: CGPoint)`, `.internal(children: [QuadTree; 4], mass: Int, centerOfMass: CGPoint)`
- Children are NW (0), NE (1), SW (2), SE (3)

---

- [ ] **Step 1: Write QuadTree struct skeleton test**

```swift
// QuadTreeTests.swift
// ABOUTME: Tests for Barnes-Hut quadtree spatial partitioning
// ABOUTME: Verifies insertion, subdivision, center-of-mass, and force approximation

import Testing
import Foundation
import CoreGraphics
@testable import NodeLifeCore

@Test func emptyTreeHasZeroMass() {
    let tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(tree.mass == 0)
}

@Test func insertSingleNode() {
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    tree.insert(index: 0, position: CGPoint(x: 50, y: 50))
    #expect(tree.mass == 1)
    #expect(tree.centerOfMass.x == 50)
    #expect(tree.centerOfMass.y == 50)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test --filter QuadTreeTests 2>&1 | tail -5`
Expected: Compilation error — `QuadTree` not defined

- [ ] **Step 3: Implement QuadTree struct with insert**

```swift
// QuadTree.swift
// ABOUTME: Barnes-Hut quadtree for O(n log n) repulsion force approximation
// ABOUTME: Partitions 2D space into quadrants, storing mass and center-of-mass per cell

import Foundation
import CoreGraphics

public struct QuadTree: Sendable {
    public var bounds: CGRect
    public private(set) var mass: Int = 0
    public private(set) var centerOfMass: CGPoint = .zero
    private var node: Node = .empty

    enum Node: Sendable {
        case empty
        case leaf(index: Int, position: CGPoint)
        case `internal`(children: QuadTreeChildren)
    }

    public init(bounds: CGRect) {
        self.bounds = bounds
    }

    public mutating func insert(index: Int, position: CGPoint) {
        // Update center of mass
        let newMass = mass + 1
        centerOfMass = CGPoint(
            x: (centerOfMass.x * CGFloat(mass) + position.x) / CGFloat(newMass),
            y: (centerOfMass.y * CGFloat(mass) + position.y) / CGFloat(newMass)
        )
        mass = newMass

        switch node {
        case .empty:
            node = .leaf(index: index, position: position)

        case .leaf(let existingIndex, let existingPos):
            // Subdivide: create 4 children, re-insert existing + new
            var children = QuadTreeChildren(parentBounds: bounds)
            children.insert(index: existingIndex, position: existingPos)
            children.insert(index: index, position: position)
            node = .internal(children: children)

        case .internal(var children):
            children.insert(index: index, position: position)
            node = .internal(children: children)
        }
    }

    /// Calculate repulsion force on a node at `position` using Barnes-Hut approximation.
    /// Returns the total force vector (fx, fy).
    public func calculateForce(
        on position: CGPoint,
        excludingIndex: Int,
        repulsionStrength: Double,
        theta: Double
    ) -> CGPoint {
        guard mass > 0 else { return .zero }

        switch node {
        case .empty:
            return .zero

        case .leaf(let index, let leafPos):
            if index == excludingIndex { return .zero }
            return repulsionForce(from: leafPos, to: position, strength: repulsionStrength)

        case .internal(let children):
            let dx = position.x - centerOfMass.x
            let dy = position.y - centerOfMass.y
            let distSq = dx * dx + dy * dy
            let cellSize = max(bounds.width, bounds.height)

            // Barnes-Hut criterion: if cell is far enough, treat as point mass
            if cellSize * cellSize / max(distSq, 1.0) < theta * theta {
                return repulsionForce(
                    from: centerOfMass, to: position,
                    strength: repulsionStrength, mass: Double(mass)
                )
            }

            // Otherwise recurse into children
            var force = CGPoint.zero
            for i in 0..<4 {
                let childForce = children[i].calculateForce(
                    on: position, excludingIndex: excludingIndex,
                    repulsionStrength: repulsionStrength, theta: theta
                )
                force.x += childForce.x
                force.y += childForce.y
            }
            return force
        }
    }

    /// Find all node indices within `distance` of `point` (for collision detection).
    public func nodesWithin(distance: Double, of point: CGPoint) -> [Int] {
        var result: [Int] = []
        collectNodesWithin(distance: distance, of: point, into: &result)
        return result
    }

    private func collectNodesWithin(distance: Double, of point: CGPoint, into result: inout [Int]) {
        // Quick reject: if the bounding rect (expanded by distance) doesn't contain the point
        let expanded = bounds.insetBy(dx: -distance, dy: -distance)
        guard expanded.contains(point) else { return }

        switch node {
        case .empty:
            break
        case .leaf(let index, let pos):
            let dx = pos.x - point.x
            let dy = pos.y - point.y
            if dx * dx + dy * dy <= distance * distance {
                result.append(index)
            }
        case .internal(let children):
            for i in 0..<4 {
                children[i].collectNodesWithin(distance: distance, of: point, into: &result)
            }
        }
    }

    private func repulsionForce(
        from source: CGPoint, to target: CGPoint,
        strength: Double, mass: Double = 1.0
    ) -> CGPoint {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let distSq = max(dx * dx + dy * dy, 1.0)
        let dist = sqrt(distSq)
        let force = strength * mass / distSq
        return CGPoint(x: (dx / dist) * force, y: (dy / dist) * force)
    }
}

/// Storage for 4 quadtree children (NW, NE, SW, SE)
struct QuadTreeChildren: Sendable {
    private var nw: QuadTree
    private var ne: QuadTree
    private var sw: QuadTree
    private var se: QuadTree

    init(parentBounds: CGRect) {
        let midX = parentBounds.midX
        let midY = parentBounds.midY
        let halfW = parentBounds.width / 2
        let halfH = parentBounds.height / 2
        nw = QuadTree(bounds: CGRect(x: parentBounds.minX, y: parentBounds.minY, width: halfW, height: halfH))
        ne = QuadTree(bounds: CGRect(x: midX, y: parentBounds.minY, width: halfW, height: halfH))
        sw = QuadTree(bounds: CGRect(x: parentBounds.minX, y: midY, width: halfW, height: halfH))
        se = QuadTree(bounds: CGRect(x: midX, y: midY, width: halfW, height: halfH))
    }

    subscript(index: Int) -> QuadTree {
        get {
            switch index {
            case 0: return nw
            case 1: return ne
            case 2: return sw
            case 3: return se
            default: fatalError("QuadTree child index out of range")
            }
        }
    }

    mutating func insert(index: Int, position: CGPoint) {
        let quadrant = quadrantFor(position)
        switch quadrant {
        case 0: nw.insert(index: index, position: position)
        case 1: ne.insert(index: index, position: position)
        case 2: sw.insert(index: index, position: position)
        case 3: se.insert(index: index, position: position)
        default: break
        }
    }

    private func quadrantFor(_ position: CGPoint) -> Int {
        let midX = nw.bounds.maxX
        let midY = nw.bounds.maxY
        if position.x <= midX {
            return position.y <= midY ? 0 : 2 // NW or SW
        } else {
            return position.y <= midY ? 1 : 3 // NE or SE
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test --filter QuadTreeTests 2>&1 | tail -10`
Expected: 2 tests PASS

- [ ] **Step 5: Write subdivision and center-of-mass tests**

```swift
@Test func insertTwoNodesSubdivides() {
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    tree.insert(index: 0, position: CGPoint(x: 25, y: 25))
    tree.insert(index: 1, position: CGPoint(x: 75, y: 75))
    #expect(tree.mass == 2)
    // Center of mass should be average
    #expect(abs(tree.centerOfMass.x - 50) < 0.01)
    #expect(abs(tree.centerOfMass.y - 50) < 0.01)
}

@Test func insertMultipleNodesCenterOfMass() {
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    tree.insert(index: 0, position: CGPoint(x: 10, y: 10))
    tree.insert(index: 1, position: CGPoint(x: 20, y: 20))
    tree.insert(index: 2, position: CGPoint(x: 30, y: 30))
    #expect(tree.mass == 3)
    #expect(abs(tree.centerOfMass.x - 20) < 0.01)
    #expect(abs(tree.centerOfMass.y - 20) < 0.01)
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test --filter QuadTreeTests 2>&1 | tail -10`
Expected: 4 tests PASS

- [ ] **Step 7: Write force approximation accuracy test**

```swift
@Test func forceApproximationWithinFivePercent() {
    // Compare Barnes-Hut force to brute-force for 20 nodes
    let nodeCount = 20
    let positions = (0..<nodeCount).map { i in
        CGPoint(x: Double.random(in: 0...500), y: Double.random(in: 0...500))
    }

    // Build tree
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 500, height: 500))
    for i in 0..<nodeCount {
        tree.insert(index: i, position: positions[i])
    }

    let strength = 200.0
    let theta = 0.8

    // Test force on node 0
    let approxForce = tree.calculateForce(
        on: positions[0], excludingIndex: 0,
        repulsionStrength: strength, theta: theta
    )

    // Brute force
    var bruteForce = CGPoint.zero
    for j in 1..<nodeCount {
        let dx = positions[0].x - positions[j].x
        let dy = positions[0].y - positions[j].y
        let distSq = max(dx * dx + dy * dy, 1.0)
        let dist = sqrt(distSq)
        let f = strength / distSq
        bruteForce.x += (dx / dist) * f
        bruteForce.y += (dy / dist) * f
    }

    // Note: signs are flipped because calculateForce returns force ON the node (away from source)
    // while brute force above calculates from node 0's perspective (same direction)
    let errorX = abs(approxForce.x - bruteForce.x) / max(abs(bruteForce.x), 0.001)
    let errorY = abs(approxForce.y - bruteForce.y) / max(abs(bruteForce.y), 0.001)
    #expect(errorX < 0.05 || abs(bruteForce.x) < 0.1)
    #expect(errorY < 0.05 || abs(bruteForce.y) < 0.1)
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test --filter QuadTreeTests 2>&1 | tail -10`
Expected: 5 tests PASS

- [ ] **Step 9: Write edge case tests**

```swift
@Test func allNodesAtSamePosition() {
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    for i in 0..<5 {
        tree.insert(index: i, position: CGPoint(x: 50, y: 50))
    }
    #expect(tree.mass == 5)
    // Force should be finite (not NaN/Inf)
    let force = tree.calculateForce(
        on: CGPoint(x: 60, y: 60), excludingIndex: -1,
        repulsionStrength: 200, theta: 0.8
    )
    #expect(force.x.isFinite)
    #expect(force.y.isFinite)
}

@Test func singleNodeForceIsZeroOnSelf() {
    var tree = QuadTree(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    tree.insert(index: 0, position: CGPoint(x: 50, y: 50))
    let force = tree.calculateForce(
        on: CGPoint(x: 50, y: 50), excludingIndex: 0,
        repulsionStrength: 200, theta: 0.8
    )
    #expect(force.x == 0)
    #expect(force.y == 0)
}
```

- [ ] **Step 10: Run tests to verify they pass**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test --filter QuadTreeTests 2>&1 | tail -10`
Expected: 7 tests PASS

- [ ] **Step 11: Commit**

```bash
git add NodeLifeCore/Sources/NodeLifeCore/Graph/QuadTree.swift NodeLifeCore/Tests/NodeLifeCoreTests/Graph/QuadTreeTests.swift
git commit -m "feat: add Barnes-Hut quadtree for O(n log n) repulsion"
```

---

## Task 2: CommunityDetection

**Files:**
- Create: `NodeLifeCore/Sources/NodeLifeCore/Graph/CommunityDetection.swift`
- Test: `NodeLifeCore/Tests/NodeLifeCoreTests/Graph/CommunityDetectionTests.swift`

### Background

Label propagation is a simple community detection algorithm. Each node starts with a unique label. Each iteration, every node adopts the most common label among its neighbors (tie-breaking: lowest label wins). After convergence (or max iterations), nodes with the same label are in the same community. The algorithm reads edge topology from the projection and writes cluster IDs into the simulation's `clusterIDs` array.

---

- [ ] **Step 1: Write failing tests for basic community detection**

```swift
// CommunityDetectionTests.swift
// ABOUTME: Tests for label propagation community detection
// ABOUTME: Verifies cluster assignment for cliques, disconnected components, and edge cases

import Testing
import Foundation
import CoreGraphics
@testable import NodeLifeCore

@Test func twoCliquesConnectedByBridgeYieldsTwoCommunities() {
    // Clique A: nodes 0,1,2 fully connected
    // Clique B: nodes 3,4,5 fully connected
    // Bridge: 2-3
    let adjacency: [[Int]] = [
        [1, 2],       // 0
        [0, 2],       // 1
        [0, 1, 3],    // 2 (bridge)
        [2, 4, 5],    // 3 (bridge)
        [3, 5],       // 4
        [3, 4],       // 5
    ]
    let labels = CommunityDetection.labelPropagation(adjacency: adjacency, maxIterations: 10)
    // Nodes 0,1,2 should share a label; nodes 3,4,5 should share a different label
    #expect(labels[0] == labels[1])
    #expect(labels[1] == labels[2])
    #expect(labels[3] == labels[4])
    #expect(labels[4] == labels[5])
    #expect(labels[0] != labels[3])
}

@Test func disconnectedComponentsGetSeparateLabels() {
    // Component A: 0-1, Component B: 2-3
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test --filter CommunityDetectionTests 2>&1 | tail -5`
Expected: Compilation error — `CommunityDetection` not defined

- [ ] **Step 3: Implement CommunityDetection**

```swift
// CommunityDetection.swift
// ABOUTME: Label propagation algorithm for graph community detection
// ABOUTME: Assigns cluster IDs to nodes based on connectivity patterns

import Foundation

public enum CommunityDetection: Sendable {
    /// Run label propagation on an adjacency list.
    /// Returns an array of cluster labels (one per node index).
    /// Each label is the lowest-numbered node index in that community.
    public static func labelPropagation(
        adjacency: [[Int]],
        maxIterations: Int = 10
    ) -> [Int] {
        let n = adjacency.count
        guard n > 0 else { return [] }

        // Each node starts with its own index as label
        var labels = Array(0..<n)

        for _ in 0..<maxIterations {
            var changed = false
            for i in 0..<n {
                let neighbors = adjacency[i]
                guard !neighbors.isEmpty else { continue }

                // Count neighbor labels
                var labelCounts: [Int: Int] = [:]
                for neighbor in neighbors {
                    labelCounts[labels[neighbor], default: 0] += 1
                }

                // Find most common label (tie-break: lowest label)
                var bestLabel = labels[i]
                var bestCount = 0
                for (label, count) in labelCounts {
                    if count > bestCount || (count == bestCount && label < bestLabel) {
                        bestLabel = label
                        bestCount = count
                    }
                }

                if bestLabel != labels[i] {
                    labels[i] = bestLabel
                    changed = true
                }
            }
            if !changed { break }
        }

        return labels
    }

    /// Build adjacency list from edge index pairs.
    /// Each entry `edgeIndices[k]` is `(sourceIndex, targetIndex)`.
    public static func buildAdjacency(nodeCount: Int, edgeIndices: [(Int, Int)]) -> [[Int]] {
        var adjacency = Array(repeating: [Int](), count: nodeCount)
        for (src, tgt) in edgeIndices {
            adjacency[src].append(tgt)
            adjacency[tgt].append(src)
        }
        return adjacency
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test --filter CommunityDetectionTests 2>&1 | tail -10`
Expected: 2 tests PASS

- [ ] **Step 5: Write additional edge case tests**

```swift
@Test func singleNodeGraph() {
    let labels = CommunityDetection.labelPropagation(adjacency: [[]], maxIterations: 10)
    #expect(labels == [0])
}

@Test func completeGraphSingleCommunity() {
    // 4 nodes, all connected to each other
    let adjacency: [[Int]] = [
        [1, 2, 3],
        [0, 2, 3],
        [0, 1, 3],
        [0, 1, 2],
    ]
    let labels = CommunityDetection.labelPropagation(adjacency: adjacency, maxIterations: 10)
    // All should have the same label
    let unique = Set(labels)
    #expect(unique.count == 1)
}

@Test func tieBreakingProducesDeterministicResults() {
    // Run twice with same input, expect same output
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test --filter CommunityDetectionTests 2>&1 | tail -10`
Expected: 7 tests PASS

- [ ] **Step 7: Commit**

```bash
git add NodeLifeCore/Sources/NodeLifeCore/Graph/CommunityDetection.swift NodeLifeCore/Tests/NodeLifeCoreTests/Graph/CommunityDetectionTests.swift
git commit -m "feat: add label propagation community detection"
```

---

## Task 3: ForceSimulation

**Files:**
- Create: `NodeLifeCore/Sources/NodeLifeCore/Graph/ForceSimulation.swift`
- Test: `NodeLifeCore/Tests/NodeLifeCoreTests/Graph/ForceSimulationTests.swift`

### Background

`ForceSimulation` is a `@MainActor` `@Observable` class that maintains parallel arrays of positions, velocities, cluster IDs, and pinned flags. It reads topology from a `GraphProjection` but does not modify it. The simulation has two phases: batch (blocking, runs N iterations synchronously) and live (tick-per-frame, driven by TimelineView).

Five forces: repulsion (Barnes-Hut), attraction (springs along edges), center gravity (linear pull), community cohesion (weak springs between same-cluster nodes), collision (radius-based overlap prevention).

Sleep/wake: simulation sleeps when kinetic energy drops below threshold, wakes on drag or data change.

The class exposes `positions: [CGPoint]` and `nodeIndex: [UUID: Int]` for the renderer.

---

- [ ] **Step 1: Write ForceSimulation test skeleton**

```swift
// ForceSimulationTests.swift
// ABOUTME: Tests for the 5-force graph simulation engine
// ABOUTME: Verifies convergence, pinning, sleep/wake, and edge cases

import Testing
import Foundation
import CoreGraphics
@testable import NodeLifeCore

// Helper to create a simple projection for testing
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test --filter ForceSimulationTests 2>&1 | tail -5`
Expected: Compilation error — `ForceSimulation` not defined

- [ ] **Step 3: Implement ForceSimulation core**

```swift
// ForceSimulation.swift
// ABOUTME: Five-force graph simulation engine with Barnes-Hut repulsion
// ABOUTME: Two-phase lifecycle (batch then live 60fps) with sleep/wake and node pinning

import Foundation
import CoreGraphics

@Observable
@MainActor
public final class ForceSimulation {
    // Parallel arrays — source of truth for rendering
    public private(set) var positions: [CGPoint] = []
    public private(set) var velocities: [CGPoint] = []
    public private(set) var clusterIDs: [Int] = []
    public private(set) var pinned: [Bool] = []
    public private(set) var nodeIndex: [UUID: Int] = [:]
    public private(set) var nodeIDs: [UUID] = []
    public private(set) var degrees: [Int] = []

    // Edge topology as index pairs for fast iteration
    private var edgeIndices: [(Int, Int)] = []
    private var edgeWeights: [Double] = []

    // Simulation state
    public private(set) var isRunning: Bool = false
    public private(set) var tickCount: Int = 0
    private var wakeTime: Date = .distantPast

    // Progressive reveal
    public private(set) var revealedCount: Int = 0
    public private(set) var revealOrder: [Int] = [] // indices sorted by degree desc

    // Force constants
    public var repulsionStrength: Double = 200.0
    public var attractionStrength: Double = 0.02
    public var centerGravity: Double = 0.3
    public var communityCohesion: Double = 0.005
    public var collisionPadding: Double = 2.0
    public var theta: Double = 0.8

    // Damping
    private var dampingStart: Double = 0.95
    private var dampingEnd: Double = 0.85
    private var dampingDecayTicks: Int = 120

    // Sleep/wake
    private var sleepThreshold: Double = 0.1
    public var minimumAwakeSeconds: Double = 0.5

    public var kineticEnergy: Double {
        velocities.reduce(0.0) { sum, v in sum + v.x * v.x + v.y * v.y }
    }

    public var isSleeping: Bool {
        !isRunning
    }

    public var nodeCount: Int { positions.count }

    public init() {}

    // MARK: - Loading

    public func load(projection: GraphProjection) {
        let nodes = projection.nodes
        let edges = projection.edges

        positions = nodes.map { $0.position }
        velocities = Array(repeating: .zero, count: nodes.count)
        pinned = Array(repeating: false, count: nodes.count)
        nodeIDs = nodes.map { $0.id }
        nodeIndex = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })

        // Build edge indices
        edgeIndices = edges.compactMap { edge -> (Int, Int)? in
            guard let si = nodeIndex[edge.sourceNodeID],
                  let ti = nodeIndex[edge.targetNodeID] else { return nil }
            return (si, ti)
        }
        edgeWeights = edges.compactMap { edge -> Double? in
            guard nodeIndex[edge.sourceNodeID] != nil,
                  nodeIndex[edge.targetNodeID] != nil else { return nil }
            return edge.weight
        }

        // Compute degrees
        degrees = Array(repeating: 0, count: nodes.count)
        for (src, tgt) in edgeIndices {
            degrees[src] += 1
            degrees[tgt] += 1
        }

        // Jitter overlapping positions
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                if positions[i] == positions[j] {
                    positions[j].x += Double.random(in: -1...1)
                    positions[j].y += Double.random(in: -1...1)
                }
            }
        }

        // Community detection
        let adjacency = CommunityDetection.buildAdjacency(
            nodeCount: nodes.count, edgeIndices: edgeIndices
        )
        clusterIDs = CommunityDetection.labelPropagation(
            adjacency: adjacency, maxIterations: 10
        )

        // Seed cluster positions: arrange clusters in a circle
        seedClusterPositions()

        // Reveal order: sorted by degree descending
        revealOrder = Array(0..<nodes.count).sorted { degrees[$0] > degrees[$1] }
        revealedCount = 0

        tickCount = 0
        isRunning = true
        wakeTime = Date()
    }

    private func seedClusterPositions() {
        guard !positions.isEmpty else { return }
        let uniqueClusters = Array(Set(clusterIDs)).sorted()
        guard uniqueClusters.count > 1 else { return }

        let clusterToAngle = Dictionary(
            uniqueKeysWithValues: uniqueClusters.enumerated().map { index, cluster in
                let angle = (Double(index) / Double(uniqueClusters.count)) * 2 * .pi
                return (cluster, angle)
            }
        )
        let radius = 150.0

        for i in 0..<positions.count {
            guard let angle = clusterToAngle[clusterIDs[i]] else { continue }
            let cx = cos(angle) * radius
            let cy = sin(angle) * radius
            positions[i] = CGPoint(
                x: cx + Double.random(in: -40...40),
                y: cy + Double.random(in: -40...40)
            )
        }
    }

    // MARK: - Batch Phase

    public func runBatch(iterations: Int = 100) {
        for _ in 0..<iterations {
            applyForces()
            integrate(damping: dampingStart)
        }
    }

    // MARK: - Live Phase

    public func tick() {
        guard isRunning else { return }

        tickCount += 1

        // Progressive reveal
        if revealedCount < positions.count {
            let perFrame = max(1, Int(ceil(Double(positions.count) / 30.0)))
            revealedCount = min(positions.count, revealedCount + perFrame)
        }

        applyForces()

        // Damping decays from start to end over dampingDecayTicks
        let t = min(1.0, Double(tickCount) / Double(dampingDecayTicks))
        let damping = dampingStart + (dampingEnd - dampingStart) * t
        integrate(damping: damping)

        // Sleep check
        let energyThreshold = sleepThreshold * Double(positions.count)
        let awakeElapsed = Date().timeIntervalSince(wakeTime)
        if kineticEnergy < energyThreshold && awakeElapsed > minimumAwakeSeconds {
            isRunning = false
        }
    }

    // MARK: - Forces

    private func applyForces() {
        guard positions.count > 0 else { return }

        // Build quadtree for repulsion
        var bounds = CGRect(
            x: positions[0].x, y: positions[0].y, width: 0, height: 0
        )
        for pos in positions {
            bounds = bounds.union(CGRect(x: pos.x, y: pos.y, width: 0, height: 0))
        }
        // Expand bounds slightly to avoid edge cases
        bounds = bounds.insetBy(dx: -50, dy: -50)

        var tree = QuadTree(bounds: bounds)
        for i in 0..<positions.count {
            tree.insert(index: i, position: positions[i])
        }

        // 1. Repulsion (Barnes-Hut)
        for i in 0..<positions.count where !pinned[i] {
            let force = tree.calculateForce(
                on: positions[i], excludingIndex: i,
                repulsionStrength: repulsionStrength, theta: theta
            )
            velocities[i].x += force.x
            velocities[i].y += force.y
        }

        // 2. Attraction (springs along edges)
        for (k, (si, ti)) in edgeIndices.enumerated() {
            let dx = positions[ti].x - positions[si].x
            let dy = positions[ti].y - positions[si].y
            let dist = max(sqrt(dx * dx + dy * dy), 1.0)
            let weight = edgeWeights[k]
            let restLength = max(30.0, 80.0 / max(weight, 0.1))
            let displacement = dist - restLength
            let force = attractionStrength * displacement
            let fx = (dx / dist) * force
            let fy = (dy / dist) * force

            if !pinned[si] {
                velocities[si].x += fx
                velocities[si].y += fy
            }
            if !pinned[ti] {
                velocities[ti].x -= fx
                velocities[ti].y -= fy
            }
        }

        // 3. Center gravity
        for i in 0..<positions.count where !pinned[i] {
            velocities[i].x -= positions[i].x * centerGravity * 0.01
            velocities[i].y -= positions[i].y * centerGravity * 0.01
        }

        // 4. Community cohesion
        if communityCohesion > 0 {
            // Compute cluster centers
            var clusterSum: [Int: (x: Double, y: Double, count: Int)] = [:]
            for i in 0..<positions.count {
                let cid = clusterIDs[i]
                var entry = clusterSum[cid, default: (0, 0, 0)]
                entry.x += positions[i].x
                entry.y += positions[i].y
                entry.count += 1
                clusterSum[cid] = entry
            }
            for i in 0..<positions.count where !pinned[i] {
                let cid = clusterIDs[i]
                guard let entry = clusterSum[cid], entry.count > 1 else { continue }
                let cx = entry.x / Double(entry.count)
                let cy = entry.y / Double(entry.count)
                velocities[i].x += (cx - positions[i].x) * communityCohesion
                velocities[i].y += (cy - positions[i].y) * communityCohesion
            }
        }

        // 5. Collision (radius-based overlap prevention using quadtree spatial query)
        let baseRadius = 6.0
        let maxCollisionDist = (baseRadius + collisionPadding) * 2
        for i in 0..<positions.count where !pinned[i] {
            let ri = baseRadius + collisionPadding
            // Query quadtree for nearby nodes within collision range
            let neighbors = tree.nodesWithin(
                distance: maxCollisionDist, of: positions[i]
            )
            for j in neighbors where j != i {
                let rj = baseRadius + collisionPadding
                let dx = positions[j].x - positions[i].x
                let dy = positions[j].y - positions[i].y
                let dist = sqrt(dx * dx + dy * dy)
                let minDist = ri + rj
                if dist < minDist && dist > 0.01 {
                    let overlap = (minDist - dist) * 0.5
                    let nx = dx / dist
                    let ny = dy / dist
                    velocities[i].x -= nx * overlap
                    velocities[i].y -= ny * overlap
                    if !pinned[j] {
                        velocities[j].x += nx * overlap
                        velocities[j].y += ny * overlap
                    }
                }
            }
        }
    }

    private func integrate(damping: Double) {
        for i in 0..<positions.count where !pinned[i] {
            velocities[i].x *= damping
            velocities[i].y *= damping
            positions[i].x += velocities[i].x
            positions[i].y += velocities[i].y
        }
    }

    // MARK: - Interaction

    public func pin(index: Int, at position: CGPoint) {
        guard index >= 0 && index < positions.count else { return }
        pinned[index] = true
        positions[index] = position
        velocities[index] = .zero
        wake()
    }

    public func unpin(index: Int) {
        guard index >= 0 && index < positions.count else { return }
        pinned[index] = false
    }

    public func moveNode(index: Int, to position: CGPoint) {
        guard index >= 0 && index < positions.count, pinned[index] else { return }
        positions[index] = position
    }

    public func wake() {
        isRunning = true
        wakeTime = Date()
        tickCount = max(tickCount, dampingDecayTicks / 2) // don't reset damping fully
    }

    public func stop() {
        isRunning = false
    }

    // MARK: - Render helpers

    /// Node radius based on degree, log-scaled between 4px and 16px
    public func nodeRadius(at index: Int) -> CGFloat {
        guard index >= 0 && index < degrees.count else { return 6 }
        let degree = max(1, degrees[index])
        let logDegree = log(Double(degree) + 1)
        let maxLogDegree = log(Double((degrees.max() ?? 1) + 1))
        let t = maxLogDegree > 0 ? logDegree / maxLogDegree : 0.5
        return 4.0 + t * 12.0
    }

    /// Opacity for progressive reveal (0 to 1 over 6 frames after reveal)
    public func nodeOpacity(at index: Int) -> Double {
        guard !revealOrder.isEmpty else { return 1.0 }
        // Find this node's reveal position
        guard let revealPos = revealOrder.firstIndex(of: index) else { return 1.0 }
        if revealPos >= revealedCount { return 0.0 }
        // Fade in over 6 frames after reveal
        let framesSinceReveal = revealedCount - revealPos
        return min(1.0, Double(framesSinceReveal) / 6.0)
    }

    /// Hit test: returns node index if point is within hit radius
    public func hitTest(point: CGPoint, zoom: CGFloat) -> Int? {
        for i in 0..<positions.count {
            let radius = nodeRadius(at: i) + 4
            let dx = point.x - positions[i].x
            let dy = point.y - positions[i].y
            if dx * dx + dy * dy <= radius * radius / (zoom * zoom) {
                return i
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test --filter ForceSimulationTests 2>&1 | tail -10`
Expected: 2 tests PASS

- [ ] **Step 5: Write sleep/wake and edge case tests**

```swift
@Test @MainActor func simulationSleepsWhenEnergyLow() async {
    let (projection, _) = makeProjection(nodeCount: 3, edges: [(0,1)])
    let sim = ForceSimulation()
    sim.minimumAwakeSeconds = 0 // disable for test speed
    sim.load(projection: projection)
    sim.runBatch(iterations: 100)

    // Tick until sleep (with safety limit)
    for _ in 0..<500 {
        if !sim.isRunning { break }
        sim.tick()
    }
    #expect(!sim.isRunning)
}

@Test @MainActor func wakeResumesSimulation() async {
    let (projection, _) = makeProjection(nodeCount: 3, edges: [(0,1)])
    let sim = ForceSimulation()
    sim.minimumAwakeSeconds = 0 // disable for test speed
    sim.load(projection: projection)
    sim.runBatch(iterations: 200)

    // Force sleep
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
    sim.minimumAwakeSeconds = 10.0 // long awake time
    sim.load(projection: projection)
    sim.runBatch(iterations: 200)

    // Even with low energy, should not sleep due to minimum awake time
    for _ in 0..<100 { sim.tick() }
    #expect(sim.isRunning) // still running because minimumAwakeSeconds hasn't elapsed
}

@Test @MainActor func allForcesProduceFiniteValues() async {
    // Two nodes at same position (zero-distance edge case)
    var nodes = [
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

    // All positions should be finite and somewhat spread out
    for pos in sim.positions {
        #expect(pos.x.isFinite)
        #expect(pos.y.isFinite)
    }
    // At least some distance between nodes
    let dx = sim.positions[0].x - sim.positions[1].x
    let dy = sim.positions[0].y - sim.positions[1].y
    #expect(sqrt(dx * dx + dy * dy) > 5)
}

@Test @MainActor func singleNodePlacedNearCenter() async {
    let (projection, _) = makeProjection(nodeCount: 1)
    let sim = ForceSimulation()
    sim.load(projection: projection)
    sim.runBatch(iterations: 50)

    // Single node should be pulled to center by gravity
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test --filter ForceSimulationTests 2>&1 | tail -10`
Expected: 9 tests PASS

- [ ] **Step 7: Commit**

```bash
git add NodeLifeCore/Sources/NodeLifeCore/Graph/ForceSimulation.swift NodeLifeCore/Tests/NodeLifeCoreTests/Graph/ForceSimulationTests.swift
git commit -m "feat: add 5-force simulation engine with Barnes-Hut and community detection"
```

---

## Task 4: GraphViewModel Updates

**Files:**
- Modify: `Sources/NodeLife/GraphViewModel.swift`

### Background

The view model currently owns a `ForceDirectedLayout` and calls it in `loadGraph()`. It needs to own a `ForceSimulation` instead, manage its lifecycle (load, batch, start live, stop on filter change), and support drag-to-pin interactions.

Key changes:
- Replace `layoutEngine: ForceDirectedLayout` with `simulation: ForceSimulation`
- `loadGraph()` loads projection, calls `simulation.load()`, runs batch, then simulation ticks are driven by the view (via `tick()`)
- Add `dragNode(index:to:)`, `startDrag(index:at:)`, `endDrag(index:)` methods
- Add `simulation` as a public property so the view can read positions

---

- [ ] **Step 1: Read the current GraphViewModel to confirm nothing has changed**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && head -20 Sources/NodeLife/GraphViewModel.swift`
Expected: Current file matches what we've read

- [ ] **Step 2: Replace ForceDirectedLayout with ForceSimulation in GraphViewModel**

Replace the entire content of `Sources/NodeLife/GraphViewModel.swift` with:

```swift
// ABOUTME: Observable view model bridging graph system to SwiftUI
// ABOUTME: Manages projection loading, simulation lifecycle, selection, camera, and filter state

import SwiftUI
import CoreGraphics
import NodeLifeCore

@Observable
@MainActor
final class GraphViewModel {
    let database: AppDatabase
    private let graphBuilder: GraphBuilder
    private let graphCache: GraphCache

    let simulation = ForceSimulation()

    var projection: GraphProjection?
    var projectionType: ProjectionType = .full
    var filter: GraphFilter = .default
    var isLoading: Bool = false
    var error: String?

    // Selection
    var selectedNodeIDs: Set<UUID> = []
    var selectedEdgeID: UUID?
    var selectedEntityID: UUID?
    var hoveredNodeID: UUID?

    // Camera
    var cameraOffset: CGPoint = .zero
    var cameraZoom: CGFloat = 1.0

    // Drag state
    private(set) var isDraggingNode: Bool = false
    private var draggedNodeIndex: Int?

    init(database: AppDatabase) {
        self.database = database
        self.graphBuilder = GraphBuilder(database: database)
        self.graphCache = GraphCache()
    }

    func loadGraph() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            if let cached = await graphCache.get(projectionType: projectionType, filter: filter) {
                projection = cached
                simulation.load(projection: cached)
                simulation.runBatch(iterations: 100)
                return
            }

            let built = try await graphBuilder.build(projectionType: projectionType, filter: filter)
            projection = built
            simulation.load(projection: built)
            simulation.runBatch(iterations: 100)

            // Write batch positions back into projection for caching
            var cachedNodes = built.nodes
            for i in 0..<cachedNodes.count {
                cachedNodes[i] = cachedNodes[i].withPosition(simulation.positions[i])
            }
            let cachedProjection = GraphProjection(
                nodes: cachedNodes, edges: built.edges,
                projectionType: built.projectionType, filter: built.filter
            )
            await graphCache.set(projection: cachedProjection, projectionType: projectionType, filter: filter)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Simulation

    func simulationTick() {
        simulation.tick()
    }

    // MARK: - Drag interaction

    func startNodeDrag(index: Int, at position: CGPoint) {
        isDraggingNode = true
        draggedNodeIndex = index
        simulation.pin(index: index, at: position)
    }

    func dragNode(to position: CGPoint) {
        guard let index = draggedNodeIndex else { return }
        simulation.moveNode(index: index, to: position)
    }

    func endNodeDrag() {
        if let index = draggedNodeIndex {
            simulation.unpin(index: index)
        }
        isDraggingNode = false
        draggedNodeIndex = nil
    }

    // MARK: - Selection

    func selectNode(_ nodeID: UUID, multiSelect: Bool = false) {
        if multiSelect {
            if selectedNodeIDs.contains(nodeID) {
                selectedNodeIDs.remove(nodeID)
            } else {
                selectedNodeIDs.insert(nodeID)
            }
        } else {
            selectedNodeIDs = [nodeID]
        }
        selectedEdgeID = nil
        selectedEntityID = projection?.nodes.first { $0.id == nodeID }?.entityID
    }

    func selectEdge(_ edgeID: UUID) {
        selectedEdgeID = edgeID
        selectedNodeIDs = []
        selectedEntityID = nil
    }

    func deselectAll() {
        selectedNodeIDs = []
        selectedEdgeID = nil
        selectedEntityID = nil
    }

    func updateProjectionType(_ type: ProjectionType) async {
        simulation.stop()
        projectionType = type
        await loadGraph()
    }

    func updateFilter(_ newFilter: GraphFilter) async {
        simulation.stop()
        filter = newFilter
        await graphCache.invalidateAll()
        await loadGraph()
    }

    func resetCamera() {
        cameraOffset = .zero
        cameraZoom = 1.0
    }
}
```

- [ ] **Step 3: Verify build succeeds**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/NodeLife/GraphViewModel.swift
git commit -m "refactor: replace ForceDirectedLayout with ForceSimulation in GraphViewModel"
```

---

## Task 5: GraphCanvasView Updates

**Files:**
- Modify: `Sources/NodeLife/Views/Graph/GraphCanvasView.swift`

### Background

The current canvas uses a static `Canvas` that reads positions from `GraphProjection.nodes[i].position`. It needs to:
1. Wrap in `TimelineView(.animation)` to drive 60fps ticks
2. Read positions from `simulation.positions[]` via `simulation.nodeIndex[]`
3. Use degree-based sizing from `simulation.nodeRadius(at:)`
4. Apply progressive reveal opacity from `simulation.nodeOpacity(at:)`
5. Split the drag gesture: hit test first — if on a node, drag the node; otherwise pan the camera
6. Use `nodeIndex` for O(1) edge endpoint lookups instead of `first(where:)`

---

- [ ] **Step 1: Replace GraphCanvasView content**

Replace the entire content of `Sources/NodeLife/Views/Graph/GraphCanvasView.swift` with:

```swift
// ABOUTME: SwiftUI Canvas-based graph renderer with pan/zoom, node dragging, and progressive reveal
// ABOUTME: Reads live positions from ForceSimulation at 60fps via TimelineView

import SwiftUI
import NodeLifeCore

struct GraphCanvasView: View {
    @Bindable var viewModel: GraphViewModel
    @State private var dragStartOffset: CGPoint = .zero
    @State private var zoomStart: CGFloat = 1.0
    @State private var lastTickDate: Date = .distantPast

    var body: some View {
        VStack(spacing: 0) {
            GraphToolbar(viewModel: viewModel)
            Divider()

            if viewModel.isLoading {
                ProgressView("Loading graph...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let projection = viewModel.projection, !projection.nodes.isEmpty {
                graphCanvas(projection: projection)
            } else {
                ContentUnavailableView("No Graph Data", systemImage: "circle.grid.3x3", description: Text("Import meetings and run extraction to build the knowledge graph"))
            }
        }
        .task {
            if viewModel.projection == nil {
                await viewModel.loadGraph()
            }
        }
        .onChange(of: viewModel.cameraOffset) { _, newValue in
            if newValue == .zero {
                dragStartOffset = .zero
            }
        }
        .onChange(of: viewModel.cameraZoom) { _, newValue in
            zoomStart = newValue
        }
    }

    @ViewBuilder
    private func graphCanvas(projection: GraphProjection) -> some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let _ = tickSimulation(date: timeline.date)
                Canvas { context, size in
                    let sim = viewModel.simulation
                    let offset = viewModel.cameraOffset
                    let zoom = viewModel.cameraZoom

                    // Build O(1) lookup for node metadata
                    let nodeMetadata: [UUID: (type: EntityKind, label: String)] = Dictionary(
                        uniqueKeysWithValues: projection.nodes.map { ($0.id, ($0.type, $0.label)) }
                    )

                    // Draw edges
                    for edge in projection.edges {
                        guard let si = sim.nodeIndex[edge.sourceNodeID],
                              let ti = sim.nodeIndex[edge.targetNodeID] else { continue }

                        let srcOpacity = sim.nodeOpacity(at: si)
                        let tgtOpacity = sim.nodeOpacity(at: ti)
                        guard srcOpacity > 0 && tgtOpacity > 0 else { continue }

                        let srcPoint = transformPoint(sim.positions[si], offset: offset, zoom: zoom, size: size)
                        let tgtPoint = transformPoint(sim.positions[ti], offset: offset, zoom: zoom, size: size)

                        var path = Path()
                        path.move(to: srcPoint)
                        path.addLine(to: tgtPoint)

                        let isSelected = edge.id == viewModel.selectedEdgeID
                        let lineWidth = max(1, edge.weight * 2 * zoom)
                        let edgeOpacity = min(srcOpacity, tgtOpacity)
                        context.stroke(path,
                            with: .color(isSelected ? .blue : .gray.opacity(0.4 * edgeOpacity)),
                            lineWidth: lineWidth)
                    }

                    // Draw nodes
                    for i in 0..<sim.nodeCount {
                        let opacity = sim.nodeOpacity(at: i)
                        guard opacity > 0 else { continue }

                        let point = transformPoint(sim.positions[i], offset: offset, zoom: zoom, size: size)
                        let radius = sim.nodeRadius(at: i) * zoom
                        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)

                        let nodeID = sim.nodeIDs[i]
                        let isSelected = viewModel.selectedNodeIDs.contains(nodeID)
                        let isHovered = viewModel.hoveredNodeID == nodeID

                        let meta = nodeMetadata[nodeID]
                        let color = nodeColor(for: meta?.type ?? .other, selected: isSelected, hovered: isHovered)

                        context.opacity = opacity
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                        context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: isSelected ? 2 : 1)

                        // Label when zoomed in
                        if zoom > 0.5 {
                            let text = Text(meta?.label ?? "").font(.caption2)
                            context.draw(text, at: CGPoint(x: point.x, y: point.y + radius + 8))
                        }
                        context.opacity = 1.0
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if !viewModel.isDraggingNode {
                                // First movement: decide node drag vs camera pan
                                let worldPoint = inverseTransformPoint(
                                    value.startLocation,
                                    offset: viewModel.cameraOffset,
                                    zoom: viewModel.cameraZoom,
                                    size: geometry.size
                                )
                                if let hitIndex = viewModel.simulation.hitTest(
                                    point: worldPoint, zoom: viewModel.cameraZoom
                                ) {
                                    viewModel.startNodeDrag(index: hitIndex, at: worldPoint)
                                }
                            }

                            if viewModel.isDraggingNode {
                                let worldPoint = inverseTransformPoint(
                                    value.location,
                                    offset: viewModel.cameraOffset,
                                    zoom: viewModel.cameraZoom,
                                    size: geometry.size
                                )
                                viewModel.dragNode(to: worldPoint)
                            } else {
                                // Camera pan
                                viewModel.cameraOffset = CGPoint(
                                    x: dragStartOffset.x + value.translation.width,
                                    y: dragStartOffset.y + value.translation.height
                                )
                            }
                        }
                        .onEnded { _ in
                            if viewModel.isDraggingNode {
                                viewModel.endNodeDrag()
                            } else {
                                dragStartOffset = viewModel.cameraOffset
                            }
                        }
                )
                .onTapGesture { location in
                    handleTap(at: location, size: geometry.size)
                }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            viewModel.cameraZoom = max(0.1, min(10.0, zoomStart * value.magnification))
                        }
                        .onEnded { _ in
                            zoomStart = viewModel.cameraZoom
                        }
                )
            }
        }
    }

    /// Tick the simulation once per TimelineView frame, outside the Canvas render closure.
    /// Uses `let _ = tickSimulation(date:)` in the TimelineView body to trigger side effects
    /// before Canvas draws. The return value is discarded; the purpose is the side effect.
    private func tickSimulation(date: Date) -> Bool {
        if date != lastTickDate {
            lastTickDate = date
            viewModel.simulationTick()
        }
        return true
    }

    private func transformPoint(_ point: CGPoint, offset: CGPoint, zoom: CGFloat, size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x * zoom) + offset.x + size.width / 2,
            y: (point.y * zoom) + offset.y + size.height / 2
        )
    }

    private func inverseTransformPoint(_ screenPoint: CGPoint, offset: CGPoint, zoom: CGFloat, size: CGSize) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - offset.x - size.width / 2) / zoom,
            y: (screenPoint.y - offset.y - size.height / 2) / zoom
        )
    }

    private func handleTap(at location: CGPoint, size: CGSize) {
        let sim = viewModel.simulation
        let worldPoint = inverseTransformPoint(
            location, offset: viewModel.cameraOffset,
            zoom: viewModel.cameraZoom, size: size
        )

        if let hitIndex = sim.hitTest(point: worldPoint, zoom: viewModel.cameraZoom) {
            viewModel.selectNode(sim.nodeIDs[hitIndex])
        } else {
            viewModel.deselectAll()
        }
    }

    private func nodeColor(for type: EntityKind, selected: Bool, hovered: Bool) -> Color {
        if selected { return .white }
        if hovered { return .yellow }
        switch type {
        case .person: return .blue
        case .organization: return .green
        case .project: return .orange
        case .concept: return .purple
        case .topic: return .pink
        case .place: return .red
        case .actionItem: return .mint
        case .blogIdea: return .cyan
        case .idea: return .yellow
        case .other: return .gray
        }
    }
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/NodeLife/Views/Graph/GraphCanvasView.swift
git commit -m "feat: TimelineView-driven graph canvas with progressive reveal and node dragging"
```

---

## Task 6: Delete ForceDirectedLayout and Update Tests

**Files:**
- Delete: `NodeLifeCore/Sources/NodeLifeCore/Graph/ForceDirectedLayout.swift`
- Delete: `NodeLifeCore/Tests/NodeLifeCoreTests/Graph/ForceDirectedLayoutTests.swift`

### Background

The old `ForceDirectedLayout` struct and its tests are fully replaced by `ForceSimulation`. No other files reference `ForceDirectedLayout` after the GraphViewModel changes in Task 4.

---

- [ ] **Step 1: Verify no remaining references to ForceDirectedLayout**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && grep -r "ForceDirectedLayout" --include="*.swift" -l`
Expected: Only `ForceDirectedLayout.swift` and `ForceDirectedLayoutTests.swift`

- [ ] **Step 2: Delete old files**

```bash
rm NodeLifeCore/Sources/NodeLifeCore/Graph/ForceDirectedLayout.swift
rm NodeLifeCore/Tests/NodeLifeCoreTests/Graph/ForceDirectedLayoutTests.swift
```

- [ ] **Step 3: Verify full build and tests pass**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift build 2>&1 | tail -5`
Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test 2>&1 | tail -20`
Expected: Build succeeds, all tests pass

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove ForceDirectedLayout, replaced by ForceSimulation"
```

---

## Task 7: Integration Smoke Test

**Files:**
- No new files; verify the full pipeline works

---

- [ ] **Step 1: Run full test suite**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift test 2>&1 | tail -30`
Expected: All tests pass (QuadTreeTests, CommunityDetectionTests, ForceSimulationTests, plus all existing tests)

- [ ] **Step 2: Run build in release mode**

Run: `cd /Users/harper/Public/src/2389/nl/NodeLife && swift build -c release 2>&1 | tail -5`
Expected: Release build succeeds

- [ ] **Step 3: Manual verification checklist**

Verify by running the app:
- Graph loads and shows clustered layout immediately (Phase 1)
- Nodes appear progressively (high-degree first) with fade-in
- Nodes are degree-sized (hub nodes are bigger)
- Dragging a node pins it and neighbors react in real time
- Releasing a node lets it settle back under forces
- Dragging empty space pans the camera
- Pinch to zoom works
- Tapping a node selects it
- Changing filter stops simulation and shows fresh layout
- Simulation settles to sleep after a few seconds
- No visible overlap between nodes

- [ ] **Step 4: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: integration fixes for graph layout engine"
```
