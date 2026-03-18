// ABOUTME: Sidebar with meeting list, entity browser, and sync status
// ABOUTME: Groups meetings by date, shows entity counts by type, and provides search

import SwiftUI
import NodeLifeCore

struct SidebarView: View {
    @Bindable var appState: AppState

    var body: some View {
        List(selection: $appState.selectedMeetingId) {
            Section("Meetings") {
                ForEach(appState.meetings) { meeting in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title)
                            .font(.headline)
                        HStack {
                            Text(meeting.date, style: .date)
                            Spacer()
                            Text(meeting.transcriptStatus.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .tag(meeting.id)
                }
            }

            Section("Entities (\(appState.entities.count))") {
                ForEach(EntityKind.allCases, id: \.self) { kind in
                    let count = appState.entities.filter { $0.kind == kind }.count
                    if count > 0 {
                        Label("\(kind.rawValue.capitalized) (\(count))", systemImage: iconForKind(kind))
                    }
                }
            }
        }
        .searchable(text: $appState.searchQuery)
        .navigationTitle("NodeLife")
        .toolbar {
            ToolbarItem {
                Button(action: { Task { await appState.sync() } }) {
                    Label("Sync", systemImage: appState.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .disabled(appState.isSyncing)
            }
        }
    }

    private func iconForKind(_ kind: EntityKind) -> String {
        switch kind {
        case .person: return "person"
        case .organization: return "building.2"
        case .project: return "hammer"
        case .concept: return "lightbulb"
        case .topic: return "tag"
        case .place: return "mappin"
        case .actionItem: return "checkmark.circle"
        case .blogIdea: return "pencil"
        case .idea: return "sparkles"
        case .other: return "questionmark.circle"
        }
    }
}
