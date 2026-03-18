// ABOUTME: Observable view model bridging graph system to SwiftUI
// ABOUTME: Manages projection loading, layout, selection, camera, and filter state

import SwiftUI
import CoreGraphics
import NodeLifeCore

@Observable
@MainActor
final class GraphViewModel {
    let database: AppDatabase
    private let graphBuilder: GraphBuilder
    private let graphCache: GraphCache
    private let layoutEngine: ForceDirectedLayout

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

    init(database: AppDatabase) {
        self.database = database
        self.graphBuilder = GraphBuilder(database: database)
        self.graphCache = GraphCache()
        self.layoutEngine = ForceDirectedLayout()
    }

    func loadGraph() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            if let cached = await graphCache.get(projectionType: projectionType, filter: filter) {
                projection = cached
                return
            }

            let built = try await graphBuilder.build(projectionType: projectionType, filter: filter)
            let positioned = await layoutEngine.layout(
                nodes: built.nodes, edges: built.edges,
                bounds: CGSize(width: 1600, height: 1200)
            )
            let final_ = GraphProjection(
                nodes: positioned, edges: built.edges,
                projectionType: built.projectionType, filter: built.filter
            )
            projection = final_
            await graphCache.set(projection: final_, projectionType: projectionType, filter: filter)
        } catch {
            self.error = error.localizedDescription
        }
    }

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
        projectionType = type
        await loadGraph()
    }

    func updateFilter(_ newFilter: GraphFilter) async {
        filter = newFilter
        await graphCache.invalidateAll()
        await loadGraph()
    }

    func resetCamera() {
        cameraOffset = .zero
        cameraZoom = 1.0
    }
}
