// ABOUTME: Step 5 of setup wizard that runs the initial Granola meeting sync
// ABOUTME: Creates SyncService for Granola source, shows progress bar, handles errors

import SwiftUI
import NodeLifeCore

struct SyncStepView: View {
    let database: AppDatabase
    let granolaEnabled: Bool
    let onFinish: () -> Void

    @State private var isSyncing = false
    @State private var isComplete = false
    @State private var hasFatalError = false
    @State private var processedCount = 0
    @State private var totalCount = 0
    @State private var skippedCount = 0
    @State private var currentSource = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if isComplete && !hasFatalError {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Done!")
                    .font(.title2.bold())

                if skippedCount > 0 {
                    Text("Imported \(processedCount) of \(totalCount) meetings (\(skippedCount) skipped)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Imported \(processedCount) meetings")
                        .foregroundStyle(.secondary)
                }

                Button("Finish") {
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if isComplete && hasFatalError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Sync Failed")
                    .font(.title2.bold())

                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 16) {
                    Button("Retry") {
                        Task {
                            hasFatalError = false
                            errorMessage = nil
                            await startSync()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Continue Anyway") {
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            } else if isSyncing {
                ProgressView(value: totalCount > 0 ? Double(processedCount) : 0, total: totalCount > 0 ? Double(totalCount) : 1)
                    .progressViewStyle(.linear)
                    .frame(width: 300)

                Text("Syncing \(currentSource)... \(processedCount) of \(totalCount)")
                    .foregroundStyle(.secondary)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Ready to Sync")
                    .font(.title2.bold())

                Text("NodeLife will import your meeting transcripts and prepare them for analysis.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Start Sync") {
                    Task {
                        await startSync()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding(40)
    }

    private func startSync() async {
        isSyncing = true
        processedCount = 0
        totalCount = 0
        skippedCount = 0

        let jobQueue = JobQueue(dbWriter: database.writer)

        // Sync Granola if enabled
        if granolaEnabled {
            do {
                let config = try GranolaConfig.fromInstalledApp()
                let adapter = GranolaSourceAdapter(config: config)
                currentSource = "Granola"
                await syncSource(adapter: adapter, jobQueue: jobQueue)
            } catch {
                hasFatalError = true
                errorMessage = "Failed to connect to Granola: \(error.localizedDescription)"
            }
        }

        isComplete = true
        isSyncing = false
    }

    private func syncSource(adapter: some SourceAdapter, jobQueue: JobQueue) async {
        let baseProcessed = processedCount
        let baseTotal = totalCount
        let service = SyncService(database: database, sourceAdapter: adapter, jobQueue: jobQueue)
        for await progress in service.sync() {
            totalCount = baseTotal + progress.totalCount
            processedCount = baseProcessed + progress.processedCount
            if progress.error != nil {
                skippedCount += 1
                errorMessage = progress.error
            }
        }
    }
}
