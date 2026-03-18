// ABOUTME: Immutable value type representing a node in a graph projection
// ABOUTME: Maps to an Entity with position, cluster, and pinning state

import Foundation
import CoreGraphics

public struct GraphNode: Identifiable, Sendable, Codable, Hashable {
    public var id: UUID
    public var entityID: UUID
    public var label: String
    public var type: EntityKind
    public var position: CGPoint
    public var isPinned: Bool
    public var clusterID: Int?
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        entityID: UUID,
        label: String,
        type: EntityKind,
        position: CGPoint = .zero,
        isPinned: Bool = false,
        clusterID: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.entityID = entityID
        self.label = label
        self.type = type
        self.position = position
        self.isPinned = isPinned
        self.clusterID = clusterID
        self.metadata = metadata
    }

    public func withPosition(_ newPosition: CGPoint) -> GraphNode {
        var copy = self
        copy.position = newPosition
        return copy
    }

    public func withClusterID(_ cluster: Int?) -> GraphNode {
        var copy = self
        copy.clusterID = cluster
        return copy
    }
}
