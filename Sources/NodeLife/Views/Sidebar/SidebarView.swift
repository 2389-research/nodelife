// ABOUTME: Sidebar with meeting list, entity browser, and sync status
// ABOUTME: Groups meetings by date, shows entity counts by type, and provides search

import SwiftUI
import NodeLifeCore

struct SidebarView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var appState: AppState

    var body: some View {
        List(selection: $appState.selectedMeetingId) {
            Section("Meetings") {
                ForEach(appState.meetings) { meeting in
                    meetingRow(meeting)
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
        .safeAreaInset(edge: .bottom) {
            statusBar
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

    // MARK: - Subviews

    private func meetingRow(_ meeting: Meeting) -> some View {
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
                    .glassEffect(.regular, in: .capsule)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            if appState.jobsPending > 0 || appState.jobsFailed > 0 {
                jobProgress
            }

            Divider()

            HStack(spacing: 12) {
                workerToggle
                Spacer()
                logButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }

    private var jobProgress: some View {
        VStack(spacing: 6) {
            if appState.jobsPending > 0 {
                ProgressView(
                    value: Double(appState.jobsCompleted),
                    total: Double(max(appState.jobsTotal, 1))
                )
            }
            HStack {
                if appState.jobsPending > 0 {
                    Text("Extracting \(appState.jobsCompleted)/\(appState.jobsTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if appState.jobsFailed > 0 {
                    Button {
                        appState.retryFailedJobs()
                    } label: {
                        Text("\(appState.jobsFailed) failed — retry")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var workerToggle: some View {
        Button {
            if appState.isJobRunnerRunning {
                appState.stopJobRunner()
            } else {
                appState.startJobRunner()
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.isJobRunnerRunning ? .green : .red)
                    .frame(width: 6, height: 6)
                Text(appState.isJobRunnerRunning ? "Workers On" : "Workers Off")
                    .font(.caption)
            }
        }
        .buttonStyle(.glass)
    }

    private var logButton: some View {
        Button {
            openWindow(id: "job-log")
        } label: {
            Label("Log", systemImage: "doc.text.magnifyingglass")
                .font(.caption)
        }
        .buttonStyle(.glass)
    }

    // MARK: - Helpers

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
