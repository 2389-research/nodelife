// ABOUTME: Step 2 of setup wizard for data source detection and selection
// ABOUTME: Auto-detects Granola directory, shows status with enable/disable toggle

import SwiftUI
import NodeLifeCore

struct DataSourceStepView: View {
    @Binding var granolaEnabled: Bool

    @State private var granolaResult: DataSourceResult?

    private let detector = DataSourceDetector()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Data Sources")
                .font(.title2.bold())

            Text("NodeLife can import meeting transcripts from the following sources:")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                sourceRow(
                    name: "Granola",
                    result: granolaResult,
                    enabled: $granolaEnabled
                )
            }

            if granolaResult?.found != true {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No data sources found.")
                        .font(.headline)
                    Text("NodeLife supports Granola meeting transcripts. Install Granola and log in, then re-run setup.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .padding(40)
        .task {
            let expandedPath = NSString(string: GranolaConfig.defaultDataPath).expandingTildeInPath
            granolaResult = detector.detectGranola(at: expandedPath)
        }
    }

    @ViewBuilder
    private func sourceRow(name: String, result: DataSourceResult?, enabled: Binding<Bool>) -> some View {
        HStack {
            if let result = result {
                if result.found {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(name)
                    Spacer()
                    Toggle("", isOn: enabled)
                        .labelsHidden()
                } else {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                    Text("\(name) — not found")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning \(name)...")
                Spacer()
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
