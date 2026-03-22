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
