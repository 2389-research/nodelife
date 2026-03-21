// ABOUTME: Log viewer for extraction job activity
// ABOUTME: Shows timestamped entries with error highlighting and auto-scroll

import SwiftUI

struct JobLogView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logList
        }
    }

    private var toolbar: some View {
        HStack {
            Text("Job Log")
                .font(.headline)

            Spacer()

            HStack(spacing: 12) {
                // Worker toggle
                Button(appState.isJobRunnerRunning ? "Stop Workers" : "Start Workers") {
                    if appState.isJobRunnerRunning {
                        appState.stopJobRunner()
                    } else {
                        appState.startJobRunner()
                    }
                }

                // Retry failed
                if appState.jobsFailed > 0 {
                    Button("Retry \(appState.jobsFailed) Failed") {
                        appState.retryFailedJobs()
                    }
                }

                // Clear log
                Button("Clear") {
                    appState.jobLogs.removeAll()
                }

                // Status indicator
                Circle()
                    .fill(appState.isJobRunnerRunning ? .green : .red)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            List(appState.jobLogs) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)

                    Text(entry.meetingTitle)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)

                    Text(entry.message)
                        .font(.caption)
                        .foregroundStyle(entry.isError ? .red : .primary)
                        .textSelection(.enabled)
                }
                .id(entry.id)
            }
            .listStyle(.plain)
            .onChange(of: appState.jobLogs.count) {
                if let last = appState.jobLogs.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}
