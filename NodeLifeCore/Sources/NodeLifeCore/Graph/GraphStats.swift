// ABOUTME: Computed statistics for a graph projection
// ABOUTME: Calculates density, average degree, and cluster count from nodes and edges

import Foundation

public struct GraphStats: Sendable, Codable {
    public var nodeCount: Int
    public var edgeCount: Int
    public var clusterCount: Int
    public var density: Double
    public var averageDegree: Double

    public init(nodeCount: Int = 0, edgeCount: Int = 0, clusterCount: Int = 0, density: Double = 0, averageDegree: Double = 0) {
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.clusterCount = clusterCount
        self.density = density
        self.averageDegree = averageDegree
    }

    public static func compute(nodes: [GraphNode], edges: [GraphEdge]) -> GraphStats {
        let n = nodes.count
        let e = edges.count
        let maxEdges = n > 1 ? Double(n * (n - 1)) / 2.0 : 0
        let density = maxEdges > 0 ? Double(e) / maxEdges : 0
        let avgDegree = n > 0 ? (Double(e) * 2.0) / Double(n) : 0
        let clusters = Set(nodes.compactMap { $0.clusterID }).count
        return GraphStats(nodeCount: n, edgeCount: e, clusterCount: clusters, density: density, averageDegree: avgDegree)
    }
}
