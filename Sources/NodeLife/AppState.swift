// ABOUTME: Observable application state for the NodeLife macOS app
// ABOUTME: Manages database, sync, job runner, selection, entities, and detail mode switching

import SwiftUI
import NodeLifeCore
import GRDB

enum DetailMode: Hashable {
    case meeting
    case graph
    case search
}

@Observable
@MainActor
final class AppState {
    let database: AppDatabase
    var meetings: [Meeting] = []
    var entities: [Entity] = []
    var selectedMeetingId: UUID?
    var searchQuery: String = ""
    var isSyncing: Bool = false
    var syncProgress: String = ""
    var detailMode: DetailMode = .meeting
    var jobsPending: Int = 0
    var jobsCompleted: Int = 0
    var jobsFailed: Int = 0
    var jobsTotal: Int = 0
    @ObservationIgnored
    private var _graphViewModel: GraphViewModel?
    var graphViewModel: GraphViewModel {
        if let vm = _graphViewModel { return vm }
        let vm = GraphViewModel(database: database)
        _graphViewModel = vm
        return vm
    }
    @ObservationIgnored
    private var jobRunner: JobRunner?
    @ObservationIgnored
    private var jobPollingTask: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
    }

    /// Start the background job runner for extraction processing
    func startJobRunner() {
        let jobQueue = JobQueue(dbWriter: database.writer)
        let runner = JobRunner(jobQueue: jobQueue, config: JobRunnerConfig(
            pollInterval: 2.0,
            maxConcurrency: 2
        ))
        self.jobRunner = runner

        let db = database
        Task.detached {
            await runner.register(kind: "extraction", handler: ClosureJobHandler { job in
                let payload = try JSONDecoder().decode(ExtractionJobPayload.self, from: job.payload)
                let meetingId = payload.meetingID

                // Step 1: Normalize transcript (cached → chunked → normalized)
                try db.write { dbConn in
                    // Set status to chunked (chunks already stored by sync)
                    if var meeting = try Meeting.fetchOne(dbConn, key: meetingId),
                       meeting.transcriptStatus == .cached {
                        meeting.transcriptStatus = .chunked
                        try meeting.update(dbConn)
                    }
                    try TranscriptNormalizer.normalize(meetingId: meetingId, in: dbConn)
                }

                // Step 2: Build LLM client from user settings
                // Read settings on main actor to avoid keychain access issues
                let llmClient = try await MainActor.run {
                    try AppState.buildLLMClient()
                }

                // Step 3: Extract entities
                let extractionService = ExtractionService(database: db, llmClient: llmClient)
                try await extractionService.extractEntities(meetingId: meetingId)

                // Step 4: Extract relationships
                let relationshipService = RelationshipExtractionService(database: db, llmClient: llmClient)
                try await relationshipService.extractRelationships(meetingId: meetingId)
            })

            try? await runner.start()
        }

        startJobPolling()
    }

    /// Poll the job queue for progress updates
    private func startJobPolling() {
        jobPollingTask?.cancel()
        jobPollingTask = Task {
            let jobQueue = JobQueue(dbWriter: database.writer)
            while !Task.isCancelled {
                do {
                    let pending = try await jobQueue.count(status: .pending)
                    let running = try await jobQueue.count(status: .running)
                    let completed = try await jobQueue.count(status: .completed)
                    let failed = try await jobQueue.count(status: .failed)
                    let total = pending + running + completed + failed

                    await MainActor.run {
                        self.jobsPending = pending + running
                        self.jobsCompleted = completed
                        self.jobsFailed = failed
                        self.jobsTotal = total
                    }

                    // Refresh entities when jobs complete
                    if completed > 0 {
                        try? loadEntities()
                    }
                } catch {}

                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Build an LLM client from the user's saved settings
    private static func buildLLMClient() throws -> any LLMClient {
        let keychain = KeychainService(serviceName: "com.nodelife.settings")
        let provider = UserDefaults.standard.string(forKey: "nodelife.llm.provider") ?? "anthropic"
        let model = UserDefaults.standard.string(forKey: "nodelife.llm.model") ?? "claude-sonnet-4-6"

        let apiKey: String
        do {
            apiKey = try keychain.retrieve(key: "\(provider)_api_key") ?? ""
        } catch {
            apiKey = ""
        }

        guard !apiKey.isEmpty else {
            throw LLMError.apiError("No API key configured. Open Settings to add one.")
        }

        if provider == "openai" {
            let baseURL = UserDefaults.standard.string(forKey: "nodelife.llm.baseURL") ?? "https://api.openai.com/v1"
            return OpenAIClient(apiKey: apiKey, model: model, baseURL: baseURL)
        } else {
            return AnthropicClient(apiKey: apiKey, model: model)
        }
    }

    func loadMeetings() throws {
        meetings = try database.read { db in
            try Meeting.order(Meeting.Columns.date.desc).fetchAll(db)
        }
    }

    func loadEntities() throws {
        entities = try database.read { db in
            try Entity.filter(Entity.Columns.mergedIntoId == nil)
                .order(Entity.Columns.name.asc)
                .fetchAll(db)
        }
    }

    func sync() async {
        isSyncing = true
        syncProgress = "Starting sync..."
        defer {
            isSyncing = false
            syncProgress = ""
        }

        do {
            let config = try GranolaConfig.fromInstalledApp()
            let adapter = GranolaSourceAdapter(config: config)
            let jobQueue = JobQueue(dbWriter: database.writer)
            let service = SyncService(database: database, sourceAdapter: adapter, jobQueue: jobQueue)

            for await progress in service.sync() {
                syncProgress = "\(progress.step) \(progress.processedCount)/\(progress.totalCount)"
                if let error = progress.error {
                    syncProgress = error
                }
            }

            try? loadMeetings()
            try? loadEntities()
        } catch {
            syncProgress = "Sync failed: \(error.localizedDescription)"
        }
    }
}
