// ABOUTME: Tests for the JobQueue actor
// ABOUTME: Verifies enqueue, claim, complete, fail, retry, and cleanup operations

import Testing
import Foundation
import GRDB
@testable import NodeLifeCore

@Test func enqueueAndClaim() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let job = try await queue.enqueue(kind: "test", payload: Data("{}".utf8))
    #expect(job.status == .pending)

    let claimed = try await queue.claim(kinds: ["test"])
    #expect(claimed != nil)
    #expect(claimed?.id == job.id)
    #expect(claimed?.status == .running)
    #expect(claimed?.startedAt != nil)
    #expect(claimed?.attempts == 1)
}

@Test func completeJob() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let job = try await queue.enqueue(kind: "test", payload: Data())
    _ = try await queue.claim(kinds: ["test"])
    try await queue.complete(jobID: job.id)

    let completed = try db.read { db in
        try Job.fetchOne(db, key: job.id)
    }
    #expect(completed?.status == .completed)
    #expect(completed?.completedAt != nil)
}

@Test func failJob() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let job = try await queue.enqueue(kind: "test", payload: Data())
    _ = try await queue.claim()
    try await queue.fail(jobID: job.id, error: "something broke")

    let failed = try db.read { db in
        try Job.fetchOne(db, key: job.id)
    }
    #expect(failed?.status == .failed)
    #expect(failed?.lastError == "something broke")
}

@Test func retryableJobs() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let job = try await queue.enqueue(kind: "test", payload: Data())
    _ = try await queue.claim()
    try await queue.fail(jobID: job.id, error: "failed once")

    let retryable = try await queue.retryable()
    #expect(retryable.count == 1)
    #expect(retryable.first?.id == job.id)
}

@Test func claimRespectsKindFilter() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    _ = try await queue.enqueue(kind: "extraction", payload: Data())
    _ = try await queue.enqueue(kind: "sync", payload: Data())

    let claimed = try await queue.claim(kinds: ["sync"])
    #expect(claimed?.kind == "sync")
}

@Test func claimReturnsPriorityFirst() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    _ = try await queue.enqueue(kind: "test", payload: Data(), priority: 0)
    _ = try await queue.enqueue(kind: "test", payload: Data(), priority: 10)

    let claimed = try await queue.claim()
    #expect(claimed?.priority == 10)
}

@Test func claimReturnsNilWhenEmpty() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let claimed = try await queue.claim()
    #expect(claimed == nil)
}

@Test func cleanupRemovesOldCompletedJobs() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    let job = try await queue.enqueue(kind: "test", payload: Data())
    _ = try await queue.claim()
    try await queue.complete(jobID: job.id)

    let removed = try await queue.cleanup(olderThan: Date().addingTimeInterval(1))
    #expect(removed == 1)

    let count = try await queue.count(status: .completed)
    #expect(count == 0)
}

@Test func countJobsByStatus() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    _ = try await queue.enqueue(kind: "a", payload: Data())
    _ = try await queue.enqueue(kind: "b", payload: Data())

    let pending = try await queue.count(status: .pending)
    #expect(pending == 2)

    let total = try await queue.count()
    #expect(total == 2)
}

@Test func completeNonexistentJobThrows() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)

    do {
        try await queue.complete(jobID: UUID())
        #expect(Bool(false), "Should have thrown")
    } catch let error as JobQueueError {
        #expect(error.errorDescription?.contains("Job not found") == true)
    }
}
