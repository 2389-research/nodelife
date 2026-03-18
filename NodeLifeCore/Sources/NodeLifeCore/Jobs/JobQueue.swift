// ABOUTME: Persistent job queue system backed by the Job database table
// ABOUTME: Provides thread-safe atomic operations for job queueing, claiming, completion, and cleanup

import Foundation
import GRDB

public actor JobQueue: Sendable {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    /// Enqueue a new job
    public func enqueue(kind: String, payload: Data, priority: Int = 0) async throws -> Job {
        return try await dbWriter.write { db in
            var job = Job(kind: kind, payload: payload, priority: priority)
            try job.insert(db)
            return job
        }
    }

    /// Atomically claim next available job
    public func claim(kinds: [String] = []) async throws -> Job? {
        return try await dbWriter.write { db in
            var query = Job
                .filter(Job.Columns.status == JobStatus.pending.rawValue)
                .filter(Job.Columns.scheduledAt <= Date())
                .order(Job.Columns.priority.desc, Job.Columns.createdAt.asc)

            if !kinds.isEmpty {
                query = query.filter(kinds.contains(Job.Columns.kind))
            }

            guard var job = try query.fetchOne(db) else { return nil }

            job.status = .running
            job.startedAt = Date()
            job.attempts += 1
            try job.update(db)
            return job
        }
    }

    /// Mark job completed
    public func complete(jobID: UUID) async throws {
        try await dbWriter.write { db in
            guard var job = try Job.fetchOne(db, key: jobID) else {
                throw JobQueueError.jobNotFound(jobID)
            }
            job.status = .completed
            job.completedAt = Date()
            try job.update(db)
        }
    }

    /// Mark job failed
    public func fail(jobID: UUID, error: String) async throws {
        try await dbWriter.write { db in
            guard var job = try Job.fetchOne(db, key: jobID) else {
                throw JobQueueError.jobNotFound(jobID)
            }
            job.status = .failed
            job.lastError = error
            try job.update(db)
        }
    }

    /// Re-enqueue a failed job for retry
    public func retry(jobID: UUID) async throws {
        try await dbWriter.write { db in
            guard var job = try Job.fetchOne(db, key: jobID) else {
                throw JobQueueError.jobNotFound(jobID)
            }
            job.status = .pending
            job.startedAt = nil
            job.lastError = nil
            try job.update(db)
        }
    }

    /// Find retryable jobs (failed but under maxAttempts)
    public func retryable() async throws -> [Job] {
        return try await dbWriter.read { db in
            try Job
                .filter(Job.Columns.status == JobStatus.failed.rawValue)
                .filter(Job.Columns.attempts < Job.Columns.maxAttempts)
                .order(Job.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    /// Clean up old completed jobs
    @discardableResult
    public func cleanup(olderThan: Date) async throws -> Int {
        return try await dbWriter.write { db in
            try Job
                .filter(Job.Columns.status == JobStatus.completed.rawValue)
                .filter(Job.Columns.completedAt < olderThan)
                .deleteAll(db)
        }
    }

    /// Count jobs by status
    public func count(status: JobStatus? = nil) async throws -> Int {
        return try await dbWriter.read { db in
            if let status {
                return try Job
                    .filter(Job.Columns.status == status.rawValue)
                    .fetchCount(db)
            } else {
                return try Job.fetchCount(db)
            }
        }
    }
}

public enum JobQueueError: LocalizedError, Sendable {
    case jobNotFound(UUID)
    case invalidPayload(String)

    public var errorDescription: String? {
        switch self {
        case .jobNotFound(let id): return "Job not found: \(id)"
        case .invalidPayload(let detail): return "Invalid payload: \(detail)"
        }
    }
}
