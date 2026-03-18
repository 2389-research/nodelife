// ABOUTME: Meeting detail view showing header and chunked transcript
// ABOUTME: Displays speaker labels, transcript status, and chunk-level text

import SwiftUI
import NodeLifeCore

struct MeetingDetailView: View {
    let meeting: Meeting
    let chunks: [MeetingChunk]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(meeting.title)
                        .font(.title)
                    HStack {
                        Text(meeting.date, style: .date)
                        Text("·")
                        Text(formatDuration(meeting.duration))
                        Spacer()
                        Text(meeting.transcriptStatus.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Divider()

                // Chunks
                if chunks.isEmpty {
                    Text(meeting.rawTranscript)
                        .font(.body)
                        .textSelection(.enabled)
                } else {
                    ForEach(chunks) { chunk in
                        VStack(alignment: .leading, spacing: 4) {
                            if let speaker = chunk.speaker {
                                Text(speaker)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                            Text(chunk.normalizedText ?? chunk.text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}
