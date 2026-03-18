// ABOUTME: Filter panel for graph projections with entity type and threshold controls
// ABOUTME: Provides toggles for entity/relationship types and sliders for weight/confidence

import SwiftUI
import NodeLifeCore

struct GraphFilterPanel: View {
    @Bindable var viewModel: GraphViewModel
    @State private var workingFilter: GraphFilter

    init(viewModel: GraphViewModel) {
        self.viewModel = viewModel
        self._workingFilter = State(initialValue: viewModel.filter)
    }

    var body: some View {
        Form {
            Section("Entity Types") {
                ForEach(EntityKind.allCases, id: \.self) { kind in
                    Toggle(kind.rawValue.capitalized, isOn: Binding(
                        get: { workingFilter.entityTypes.contains(kind) },
                        set: { on in
                            if on { workingFilter.entityTypes.insert(kind) }
                            else { workingFilter.entityTypes.remove(kind) }
                        }
                    ))
                }
            }

            Section("Thresholds") {
                VStack(alignment: .leading) {
                    Text("Min Edge Weight: \(workingFilter.minEdgeWeight, specifier: "%.1f")")
                    Slider(value: $workingFilter.minEdgeWeight, in: 0...10)
                }
                VStack(alignment: .leading) {
                    Text("Min Confidence: \(Int(workingFilter.minConfidence * 100))%")
                    Slider(value: $workingFilter.minConfidence, in: 0...1)
                }
            }

            Section("Limits") {
                Stepper("Max Nodes: \(workingFilter.maxNodes)", value: $workingFilter.maxNodes, in: 10...2000, step: 50)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Reset") { workingFilter = .default }
                Spacer()
                Button("Apply") {
                    Task { await viewModel.updateFilter(workingFilter) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
