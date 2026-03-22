// ABOUTME: Label propagation algorithm for graph community detection
// ABOUTME: Assigns cluster IDs to nodes based on connectivity patterns

import Foundation

public enum CommunityDetection: Sendable {
    /// Runs label propagation on an adjacency list. Each node starts with a unique label,
    /// then iteratively adopts the most common label among its neighbors.
    /// Tie-break: lowest label wins. Stops early if no labels change.
    public static func labelPropagation(
        adjacency: [[Int]],
        maxIterations: Int = 10
    ) -> [Int] {
        let n = adjacency.count
        guard n > 0 else { return [] }

        var labels = Array(0..<n)

        for _ in 0..<maxIterations {
            var changed = false
            var newLabels = labels
            for i in 0..<n {
                let neighbors = adjacency[i]
                guard !neighbors.isEmpty else { continue }

                // Include node's own label in the vote to stabilize small components
                var labelCounts: [Int: Int] = [labels[i]: 1]
                for neighbor in neighbors {
                    labelCounts[labels[neighbor], default: 0] += 1
                }

                var bestLabel = labels[i]
                var bestCount = 0
                for (label, count) in labelCounts {
                    if count > bestCount || (count == bestCount && label < bestLabel) {
                        bestLabel = label
                        bestCount = count
                    }
                }

                if bestLabel != labels[i] {
                    newLabels[i] = bestLabel
                    changed = true
                }
            }
            labels = newLabels
            if !changed { break }
        }

        return labels
    }

    /// Builds an adjacency list from edge index pairs. Each edge is treated as undirected.
    public static func buildAdjacency(nodeCount: Int, edgeIndices: [(Int, Int)]) -> [[Int]] {
        var adjacency = Array(repeating: [Int](), count: nodeCount)
        for (src, tgt) in edgeIndices {
            adjacency[src].append(tgt)
            adjacency[tgt].append(src)
        }
        return adjacency
    }
}
