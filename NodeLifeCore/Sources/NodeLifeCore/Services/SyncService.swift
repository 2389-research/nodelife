// ABOUTME: Orchestrates meeting import from a SourceAdapter into the local database
// ABOUTME: Deduplicates by sourceID+sourceAdapter, stores chunks, and enqueues extraction jobs

import Foundation
import GRDB

/// Progress reporting for sync operations
public struct SyncProgress: Sendable, Equatable {
    /// Description of the current step
    public let step: String
    /// Number of items processed so far
    public let processedCount: Int
    /// Total number of items to process
    public let totalCount: Int
    /// Error encountered during this step, if any
    public let error: String?
    /// Whether the sync operation is complete
    public let isComplete: Bool

    public init(
        step: String,
        processedCount: Int = 0,
        totalCount: Int = 0,
        error: String? = nil,
        isComplete: Bool = false
    ) {
        self.step = step
        self.processedCount = processedCount
        self.totalCount = totalCount
        self.error = error
        self.isComplete = isComplete
    }
}

/// Errors specific to the sync service
public enum SyncServiceError: Error, Equatable, Sendable {
    case meetingNotFound(String)
    case importFailed(String)
    case chunkStorageFailed(String)
}

/// Payload used when enqueuing extraction jobs
public struct ExtractionJobPayload: Codable, Sendable {
    public let meetingID: UUID
    public let sourceAdapter: String

    public init(meetingID: UUID, sourceAdapter: String) {
        self.meetingID = meetingID
        self.sourceAdapter = sourceAdapter
    }
}

/// Service that syncs meetings from a SourceAdapter into the local database
public struct SyncService: Sendable {
    private let database: AppDatabase
    private let sourceAdapter: any SourceAdapter
    private let jobQueue: JobQueue

    public init(database: AppDatabase, sourceAdapter: any SourceAdapter, jobQueue: JobQueue) {
        self.database = database
        self.sourceAdapter = sourceAdapter
        self.jobQueue = jobQueue
    }

    /// Run a full sync, returning an AsyncStream of progress updates
    /// - Parameter since: Optional date to limit which meetings are fetched from the adapter
    /// - Returns: An AsyncStream emitting SyncProgress updates
    public func sync(since: Date? = nil) -> AsyncStream<SyncProgress> {
        AsyncStream { continuation in
            let db = self.database
            let adapter = self.sourceAdapter
            let queue = self.jobQueue

            Task {
                do {
                    continuation.yield(SyncProgress(step: "Listing meetings"))

                    let remoteMeetings = try await adapter.listMeetings(since: since)

                    let meetingsToImport = try filterMeetingsForSync(
                        remoteMeetings,
                        adapterID: adapter.metadata.id,
                        database: db
                    )

                    let total = meetingsToImport.count
                    continuation.yield(SyncProgress(
                        step: "Importing meetings",
                        processedCount: 0,
                        totalCount: total
                    ))

                    for (index, meeting) in meetingsToImport.enumerated() {
                        do {
                            try await importNewMeeting(meeting, adapter: adapter, database: db, jobQueue: queue)
                            continuation.yield(SyncProgress(
                                step: "Importing meetings",
                                processedCount: index + 1,
                                totalCount: total
                            ))
                        } catch {
                            continuation.yield(SyncProgress(
                                step: "Importing meetings",
                                processedCount: index + 1,
                                totalCount: total,
                                error: "Failed to import \(meeting.sourceID): \(error.localizedDescription)"
                            ))
                        }
                    }

                    continuation.yield(SyncProgress(
                        step: "Sync complete",
                        processedCount: total,
                        totalCount: total,
                        isComplete: true
                    ))
                } catch {
                    continuation.yield(SyncProgress(
                        step: "Sync failed",
                        error: error.localizedDescription,
                        isComplete: true
                    ))
                }
                continuation.finish()
            }
        }
    }

    /// Sync a single meeting by its source ID
    /// - Parameter id: The source-specific identifier for the meeting
    public func syncMeeting(id: String) async throws {
        let meeting = try await sourceAdapter.fetchMeeting(id: id)
        try await importNewMeeting(meeting, adapter: sourceAdapter, database: database, jobQueue: jobQueue)
    }

    // MARK: - Private Helpers

    /// Filter out meetings that already exist in the database (by sourceID + sourceAdapter)
    private func filterMeetingsForSync(
        _ meetings: [Meeting],
        adapterID: String,
        database: AppDatabase
    ) throws -> [Meeting] {
        let sourceIDs = meetings.map(\.sourceID)
        guard !sourceIDs.isEmpty else { return [] }

        let existingSourceIDs: Set<String> = try database.read { db in
            let rows = try Meeting
                .filter(sourceIDs.contains(Meeting.Columns.sourceID))
                .filter(Meeting.Columns.sourceAdapter == adapterID)
                .select(Meeting.Columns.sourceID)
                .fetchAll(db)
            return Set(rows.map(\.sourceID))
        }

        return meetings.filter { !existingSourceIDs.contains($0.sourceID) }
    }

    /// Import a single new meeting: store it, fetch chunks, store chunks, enqueue extraction
    private func importNewMeeting(
        _ meeting: Meeting,
        adapter: any SourceAdapter,
        database: AppDatabase,
        jobQueue: JobQueue
    ) async throws {
        // Store the meeting with transcriptStatus = .cached
        var meetingToStore = meeting
        meetingToStore.transcriptStatus = .cached
        meetingToStore.sourceAdapter = adapter.metadata.id
        meetingToStore.importedAt = Date()
        meetingToStore.updatedAt = Date()

        try database.write { db in
            try meetingToStore.insert(db)
        }

        // Fetch and store transcript chunks
        let chunks = try await adapter.fetchTranscript(meetingID: meeting.id)
        try storeMeetingChunks(chunks, database: database)

        // Enqueue extraction job
        try await enqueueExtractionJob(
            meetingID: meeting.id,
            sourceAdapter: adapter.metadata.id,
            jobQueue: jobQueue
        )
    }

    /// Store transcript chunks in the database
    private func storeMeetingChunks(_ chunks: [MeetingChunk], database: AppDatabase) throws {
        guard !chunks.isEmpty else { return }
        try database.write { db in
            for var chunk in chunks {
                try chunk.insert(db)
            }
        }
    }

    /// Enqueue an extraction job for the given meeting
    private func enqueueExtractionJob(
        meetingID: UUID,
        sourceAdapter: String,
        jobQueue: JobQueue
    ) async throws {
        let payload = ExtractionJobPayload(meetingID: meetingID, sourceAdapter: sourceAdapter)
        let payloadData = try JSONEncoder().encode(payload)
        _ = try await jobQueue.enqueue(kind: "extraction", payload: payloadData)
    }
}
