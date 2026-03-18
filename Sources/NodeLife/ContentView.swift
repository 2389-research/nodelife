// ABOUTME: Root content view with 3-pane NavigationSplitView layout
// ABOUTME: Sidebar shows meeting list, detail shows selected meeting transcript

import SwiftUI
import NodeLifeCore

struct ContentView: View {
    @State var appState: AppState

    var body: some View {
        NavigationSplitView {
            // Sidebar: meeting list
            List(appState.meetings, selection: $appState.selectedMeetingId) { meeting in
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.headline)
                    Text(meeting.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(meeting.id)
            }
            .navigationTitle("Meetings")
            .searchable(text: $appState.searchQuery)
        } detail: {
            if let meetingId = appState.selectedMeetingId,
               let meeting = appState.meetings.first(where: { $0.id == meetingId }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(meeting.title)
                        .font(.title)
                    Text(meeting.date, style: .date)
                        .foregroundStyle(.secondary)
                    Divider()
                    ScrollView {
                        Text(meeting.rawTranscript)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            } else {
                ContentUnavailableView("Select a Meeting", systemImage: "doc.text", description: Text("Choose a meeting from the sidebar"))
            }
        }
        .task {
            try? appState.loadMeetings()
        }
    }
}
