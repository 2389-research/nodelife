// ABOUTME: Step 2 of setup wizard for data source detection and selection
// ABOUTME: Auto-detects Granola and Muesli directories, shows counts with enable/disable toggles

import SwiftUI
import NodeLifeCore

struct DataSourceStepView: View {
    @Binding var granolaEnabled: Bool
    @Binding var granolaPath: String
    @Binding var muesliEnabled: Bool
    @Binding var muesliPath: String

    @State private var granolaResult: DataSourceResult?
    @State private var muesliResult: DataSourceResult?

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

                sourceRow(
                    name: "Muesli",
                    result: muesliResult,
                    enabled: $muesliEnabled
                )
            }

            if granolaResult?.found != true && muesliResult?.found != true {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No data sources found.")
                        .font(.headline)
                    Text("NodeLife supports Granola and Muesli meeting transcripts. Install one of these apps and record some meetings, then re-run setup.")
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
            let expandedGranolaPath = NSString(string: granolaPath).expandingTildeInPath
            let expandedMuesliPath = NSString(string: muesliPath).expandingTildeInPath
            granolaResult = detector.detectGranola(at: expandedGranolaPath)
            muesliResult = detector.detectMuesli(at: expandedMuesliPath)
        }
    }

    @ViewBuilder
    private func sourceRow(name: String, result: DataSourceResult?, enabled: Binding<Bool>) -> some View {
        HStack {
            if let result = result {
                if result.found {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(name) (\(result.meetingCount) meetings)")
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
