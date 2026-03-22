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
    private var cachedMaxLogDegree: Double = 0

    // Edge topology as index pairs for fast iteration
    private var edgeIndices: [(Int, Int)] = []
    private var edgeWeights: [Double] = []

    // Simulation state
    public private(set) var isRunning: Bool = false
    public private(set) var tickCount: Int = 0
    private var wakeTime: Date = .distantPast

    // Progressive reveal
    public private(set) var revealedCount: Int = 0
    public private(set) var revealOrder: [Int] = []
    private var revealPosition: [Int] = []  // reverse lookup: revealPosition[nodeIndex] = position in revealOrder

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

        let resolvedEdges: [(Int, Int, Double)] = edges.compactMap { edge in
            guard let si = nodeIndex[edge.sourceNodeID],
                  let ti = nodeIndex[edge.targetNodeID] else { return nil }
            return (si, ti, edge.weight)
        }
        edgeIndices = resolvedEdges.map { ($0.0, $0.1) }
        edgeWeights = resolvedEdges.map { $0.2 }

        degrees = Array(repeating: 0, count: nodes.count)
        for (src, tgt) in edgeIndices {
            degrees[src] += 1
            degrees[tgt] += 1
        }
        cachedMaxLogDegree = log(Double((degrees.max() ?? 1) + 1))

        // Community detection
        let adjacency = CommunityDetection.buildAdjacency(
            nodeCount: nodes.count, edgeIndices: edgeIndices
        )
        clusterIDs = CommunityDetection.labelPropagation(
            adjacency: adjacency, maxIterations: 10
        )

        seedClusterPositions()

        // Jitter any remaining overlapping positions (e.g. single-cluster graphs)
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                if positions[i] == positions[j] {
                    positions[j].x += Double.random(in: -1...1)
                    positions[j].y += Double.random(in: -1...1)
                }
            }
        }

        revealOrder = Array(0..<nodes.count).sorted { degrees[$0] > degrees[$1] }
        revealPosition = Array(repeating: 0, count: nodes.count)
        for (pos, nodeIdx) in revealOrder.enumerated() {
            revealPosition[nodeIdx] = pos
        }
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

        if revealedCount < positions.count {
            let perFrame = max(1, Int(ceil(Double(positions.count) / 30.0)))
            revealedCount = min(positions.count, revealedCount + perFrame)
        }

        applyForces()

        let t = min(1.0, Double(tickCount) / Double(dampingDecayTicks))
        let damping = dampingStart + (dampingEnd - dampingStart) * t
        integrate(damping: damping)

        let energyThreshold = sleepThreshold * Double(positions.count)
        let awakeElapsed = Date().timeIntervalSince(wakeTime)
        if kineticEnergy < energyThreshold && awakeElapsed > minimumAwakeSeconds {
            isRunning = false
        }
    }

    // MARK: - Forces

    private func applyForces() {
        guard positions.count > 0 else { return }

        var bounds = CGRect(
            x: positions[0].x, y: positions[0].y, width: 0, height: 0
        )
        for pos in positions {
            bounds = bounds.union(CGRect(x: pos.x, y: pos.y, width: 0, height: 0))
        }
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
        for i in 0..<positions.count {
            let ri = baseRadius + collisionPadding
            let neighbors = tree.nodesWithin(distance: maxCollisionDist, of: positions[i])
            for j in neighbors where j > i {
                let rj = baseRadius + collisionPadding
                let dx = positions[j].x - positions[i].x
                let dy = positions[j].y - positions[i].y
                let dist = sqrt(dx * dx + dy * dy)
                let minDist = ri + rj
                if dist < minDist && dist > 0.01 {
                    let overlap = (minDist - dist) * 0.5
                    let nx = dx / dist
                    let ny = dy / dist
                    if !pinned[i] {
                        velocities[i].x -= nx * overlap
                        velocities[i].y -= ny * overlap
                    }
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
        tickCount = dampingDecayTicks / 2
    }

    public func stop() {
        isRunning = false
    }

    // MARK: - Render helpers

    public func nodeRadius(at index: Int) -> CGFloat {
        guard index >= 0 && index < degrees.count else { return 6 }
        let degree = max(1, degrees[index])
        let logDegree = log(Double(degree) + 1)
        let t = cachedMaxLogDegree > 0 ? logDegree / cachedMaxLogDegree : 0.5
        return 4.0 + t * 12.0
    }

    public func nodeOpacity(at index: Int) -> Double {
        guard !revealPosition.isEmpty, index < revealPosition.count else { return 1.0 }
        let revealPos = revealPosition[index]
        if revealPos >= revealedCount { return 0.0 }
        let framesSinceReveal = revealedCount - revealPos
        return min(1.0, Double(framesSinceReveal) / 6.0)
    }

    public func hitTest(point: CGPoint, zoom: CGFloat) -> Int? {
        let tapPadding = 4.0 / zoom
        for i in 0..<positions.count {
            guard nodeOpacity(at: i) > 0 else { continue }
            let radius = nodeRadius(at: i) + tapPadding
            let dx = point.x - positions[i].x
            let dy = point.y - positions[i].y
            if dx * dx + dy * dy <= radius * radius {
                return i
            }
        }
        return nil
    }
}
