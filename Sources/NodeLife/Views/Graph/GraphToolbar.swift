// ABOUTME: Toolbar with projection picker, stats display, filter button, and camera controls
// ABOUTME: Sits above the graph canvas providing graph-mode controls

import SwiftUI
import NodeLifeCore

struct GraphToolbar: View {
    @Bindable var viewModel: GraphViewModel
    @State private var showingFilter = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                // Projection type picker
                Menu {
                    Button("Full Graph") { Task { await viewModel.updateProjectionType(.full) } }
                    Button("Semantic") { Task { await viewModel.updateProjectionType(.semantic) } }
                    Button("Co-occurrence") { Task { await viewModel.updateProjectionType(.cooccurrence) } }
                } label: {
                    Label(viewModel.projectionType.description, systemImage: "circle.grid.3x3")
                }
                .buttonStyle(.glass)

                Spacer()

                // Stats
                if let projection = viewModel.projection {
                    Text("\(projection.stats.nodeCount) nodes, \(projection.stats.edgeCount) edges")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                }

                Spacer()

                // Filter
                Button(action: { showingFilter.toggle() }) {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.glass)
                .popover(isPresented: $showingFilter) {
                    GraphFilterPanel(viewModel: viewModel)
                        .frame(width: 300, height: 400)
                }

                // Camera
                Button(action: { viewModel.resetCamera() }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)

                // Reload
                Button(action: { Task { await viewModel.loadGraph() } }) {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
