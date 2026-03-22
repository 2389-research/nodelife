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
            TimelineView(.animation(paused: !viewModel.simulation.isRunning)) { timeline in
                let _ = tickSimulation(date: timeline.date)
                Canvas { context, size in
                    let sim = viewModel.simulation
                    let offset = viewModel.cameraOffset
                    let zoom = viewModel.cameraZoom
                    let nodeMetadata = viewModel.nodeMetadata

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
