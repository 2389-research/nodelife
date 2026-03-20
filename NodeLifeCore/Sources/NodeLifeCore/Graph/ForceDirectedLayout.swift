// ABOUTME: Force-directed layout engine using Coulomb repulsion and Hooke attraction
// ABOUTME: Positions graph nodes via iterative physics simulation with damping

import Foundation
import CoreGraphics

public struct ForceDirectedLayout: Sendable {
    public var iterations: Int
    public var repulsionStrength: Double
    public var attractionStrength: Double
    public var damping: Double

    public init(
        iterations: Int = 300,
        repulsionStrength: Double = 100.0,
        attractionStrength: Double = 0.01,
        damping: Double = 0.9
    ) {
        self.iterations = iterations
        self.repulsionStrength = repulsionStrength
        self.attractionStrength = attractionStrength
        self.damping = damping
    }

    public func layout(nodes: [GraphNode], edges: [GraphEdge], bounds: CGSize) async -> [GraphNode] {
        guard !nodes.isEmpty else { return [] }

        // Jitter overlapping nodes so repulsion forces have a direction
        var positions = nodes.map { $0.position }
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                if positions[i] == positions[j] {
                    positions[j].x += Double.random(in: -1...1)
                    positions[j].y += Double.random(in: -1...1)
                }
            }
        }
        var velocities = Array(repeating: CGPoint.zero, count: nodes.count)
        let pinnedFlags = nodes.map { $0.isPinned }

        // Build edge index (source index, target index)
        let nodeIDToIndex = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        let edgeIndices = edges.compactMap { edge -> (Int, Int)? in
            guard let si = nodeIDToIndex[edge.sourceNodeID],
                  let ti = nodeIDToIndex[edge.targetNodeID] else { return nil }
            return (si, ti)
        }

        for iteration in 0..<iterations {
            // Repulsive forces (Coulomb's law) between all pairs
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let dx = positions[i].x - positions[j].x
                    let dy = positions[i].y - positions[j].y
                    let distSq = max(dx * dx + dy * dy, 1.0)
                    let force = repulsionStrength / distSq
                    let dist = sqrt(distSq)
                    let fx = (dx / dist) * force
                    let fy = (dy / dist) * force

                    if !pinnedFlags[i] {
                        velocities[i].x += fx
                        velocities[i].y += fy
                    }
                    if !pinnedFlags[j] {
                        velocities[j].x -= fx
                        velocities[j].y -= fy
                    }
                }
            }

            // Attractive forces (Hooke's law) along edges
            for (si, ti) in edgeIndices {
                let dx = positions[ti].x - positions[si].x
                let dy = positions[ti].y - positions[si].y
                let dist = max(sqrt(dx * dx + dy * dy), 1.0)
                let force = attractionStrength * dist
                let fx = (dx / dist) * force
                let fy = (dy / dist) * force

                if !pinnedFlags[si] {
                    velocities[si].x += fx
                    velocities[si].y += fy
                }
                if !pinnedFlags[ti] {
                    velocities[ti].x -= fx
                    velocities[ti].y -= fy
                }
            }

            // Update positions with damping
            for i in 0..<nodes.count {
                guard !pinnedFlags[i] else { continue }
                velocities[i].x *= damping
                velocities[i].y *= damping
                positions[i].x += velocities[i].x
                positions[i].y += velocities[i].y

                // Clamp to bounds
                positions[i].x = max(-bounds.width / 2, min(bounds.width / 2, positions[i].x))
                positions[i].y = max(-bounds.height / 2, min(bounds.height / 2, positions[i].y))
            }

            // Yield periodically to avoid blocking
            if iteration % 50 == 0 {
                await Task.yield()
            }
        }

        return nodes.enumerated().map { index, node in
            node.withPosition(positions[index])
        }
    }
}
