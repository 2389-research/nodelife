// ABOUTME: Step 4 of setup wizard for extraction mode selection
// ABOUTME: Toggle between Quick (2-pass) and Deep (5-pass) extraction with descriptions

import SwiftUI

struct ExtractionModeStepView: View {
    @Binding var extractionMode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Extraction Mode")
                .font(.title2.bold())

            Text("Choose how thoroughly NodeLife analyzes your meeting transcripts.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                modeCard(
                    title: "Quick (2-pass)",
                    description: "Extracts entities and relationships in 2 passes. Faster, good for most meetings.",
                    tag: "quick",
                    systemImage: "hare"
                )

                modeCard(
                    title: "Deep (5-pass)",
                    description: "Full 5-pass extraction: persons, orgs/projects, themes, relationships, merge recommendations. More thorough, uses more API calls.",
                    tag: "deep",
                    systemImage: "tortoise"
                )
            }

            Spacer()
        }
        .padding(40)
    }

    @ViewBuilder
    private func modeCard(title: String, description: String, tag: String, systemImage: String) -> some View {
        Button {
            extractionMode = tag
        } label: {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if extractionMode == tag {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.title3)
                }
            }
            .padding(16)
            .background(extractionMode == tag ? Color.accentColor.opacity(0.1) : Color.clear)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(extractionMode == tag ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
