// ABOUTME: Root content view with 3-pane NavigationSplitView layout
// ABOUTME: Sidebar, detail (meeting/graph/search), and inspector panes

import SwiftUI
import NodeLifeCore
import GRDB

struct ContentView: View {
    @State var appState: AppState
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
        } detail: {
            detailContent
        }
        .inspector(isPresented: .constant(appState.graphViewModel.selectedEntityID != nil)) {
            if let entityID = appState.graphViewModel.selectedEntityID {
                InspectorView(entityID: entityID, database: appState.database)
                    .inspectorColumnWidth(min: 200, ideal: 280, max: 400)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $appState.detailMode) {
                    Label("Meetings", systemImage: "doc.text").tag(DetailMode.meeting)
                    Label("Graph", systemImage: "circle.grid.3x3").tag(DetailMode.graph)
                }
                .pickerStyle(.segmented)
            }
        }
        .task {
            try? appState.loadMeetings()
            try? appState.loadEntities()
            appState.startJobRunner()
        }
        .sheet(isPresented: Binding(
            get: { !hasCompletedSetup },
            set: { _ in }
        )) {
            SetupWizardView(database: appState.database, onFinish: {
                hasCompletedSetup = true
                try? appState.loadMeetings()
                try? appState.loadEntities()
            })
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch appState.detailMode {
        case .meeting:
            if let meetingId = appState.selectedMeetingId,
               let meeting = appState.meetings.first(where: { $0.id == meetingId }) {
                let chunks = (try? appState.database.read { db in
                    try MeetingChunk
                        .filter(MeetingChunk.Columns.meetingID == meetingId)
                        .order(MeetingChunk.Columns.chunkIndex.asc)
                        .fetchAll(db)
                }) ?? []
                MeetingDetailView(meeting: meeting, chunks: chunks)
            } else {
                ContentUnavailableView("Select a Meeting", systemImage: "doc.text", description: Text("Choose a meeting from the sidebar"))
            }
        case .graph:
            GraphCanvasView(viewModel: appState.graphViewModel)
        case .search:
            ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Enter a search query in the sidebar"))
        }
    }
}
