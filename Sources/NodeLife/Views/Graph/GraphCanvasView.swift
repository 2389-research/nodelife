// ABOUTME: SwiftUI Canvas-based graph renderer with pan/zoom and node selection
// ABOUTME: Draws edges as lines and nodes as colored circles with labels

import SwiftUI
import NodeLifeCore

struct GraphCanvasView: View {
    @Bindable var viewModel: GraphViewModel
    @State private var dragStartOffset: CGPoint = .zero
    @State private var zoomStart: CGFloat = 1.0

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
            // Sync drag baseline when camera is reset externally
            if newValue == .zero {
                dragStartOffset = .zero
            }
        }
        .onChange(of: viewModel.cameraZoom) { _, newValue in
            // Sync zoom baseline when camera is reset externally
            zoomStart = newValue
        }
    }

    @ViewBuilder
    private func graphCanvas(projection: GraphProjection) -> some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let offset = viewModel.cameraOffset
                let zoom = viewModel.cameraZoom

                // Draw edges
                for edge in projection.edges {
                    guard let src = projection.nodes.first(where: { $0.id == edge.sourceNodeID }),
                          let tgt = projection.nodes.first(where: { $0.id == edge.targetNodeID }) else { continue }

                    let srcPoint = transformPoint(src.position, offset: offset, zoom: zoom, size: size)
                    let tgtPoint = transformPoint(tgt.position, offset: offset, zoom: zoom, size: size)

                    var path = Path()
                    path.move(to: srcPoint)
                    path.addLine(to: tgtPoint)

                    let isSelected = edge.id == viewModel.selectedEdgeID
                    let lineWidth = max(1, edge.weight * 2 * zoom)
                    context.stroke(path,
                        with: .color(isSelected ? .blue : .gray.opacity(0.4)),
                        lineWidth: lineWidth)
                }

                // Draw nodes
                for node in projection.nodes {
                    let point = transformPoint(node.position, offset: offset, zoom: zoom, size: size)
                    let radius = max(4, 8 * zoom)
                    let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)

                    let isSelected = viewModel.selectedNodeIDs.contains(node.id)
                    let isHovered = viewModel.hoveredNodeID == node.id
                    let color = nodeColor(for: node.type, selected: isSelected, hovered: isHovered)

                    context.fill(Path(ellipseIn: rect), with: .color(color))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: isSelected ? 2 : 1)

                    // Label when zoomed in
                    if zoom > 0.5 {
                        let text = Text(node.label).font(.caption2)
                        context.draw(text, at: CGPoint(x: point.x, y: point.y + radius + 8))
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        viewModel.cameraOffset = CGPoint(
                            x: dragStartOffset.x + value.translation.width,
                            y: dragStartOffset.y + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        dragStartOffset = viewModel.cameraOffset
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

    private func transformPoint(_ point: CGPoint, offset: CGPoint, zoom: CGFloat, size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x * zoom) + offset.x + size.width / 2,
            y: (point.y * zoom) + offset.y + size.height / 2
        )
    }

    private func handleTap(at location: CGPoint, size: CGSize) {
        guard let projection = viewModel.projection else { return }
        let zoom = viewModel.cameraZoom
        let radius: CGFloat = max(4, 8 * zoom) + 4

        for node in projection.nodes {
            let nodeScreen = transformPoint(node.position, offset: viewModel.cameraOffset, zoom: zoom, size: size)
            let dist = hypot(location.x - nodeScreen.x, location.y - nodeScreen.y)
            if dist <= radius {
                viewModel.selectNode(node.id)
                return
            }
        }
        viewModel.deselectAll()
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
