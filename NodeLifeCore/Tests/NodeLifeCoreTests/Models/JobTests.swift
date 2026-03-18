// ABOUTME: Tests for the Job model record
// ABOUTME: Verifies GRDB conformance, default values, and job status enum

import Testing
import Foundation
@testable import NodeLifeCore

@Test func jobCreationWithDefaults() {
    let job = Job(kind: "extract", payload: Data("{}".utf8))
    #expect(job.status == .pending)
    #expect(job.priority == 0)
    #expect(job.attempts == 0)
    #expect(job.maxAttempts == 3)
    #expect(job.lastError == nil)
    #expect(job.startedAt == nil)
    #expect(job.completedAt == nil)
}

@Test func jobTableName() {
    #expect(Job.databaseTableName == "jobs")
}

@Test func jobStatusRawValues() {
    #expect(JobStatus.pending.rawValue == "pending")
    #expect(JobStatus.running.rawValue == "running")
    #expect(JobStatus.completed.rawValue == "completed")
    #expect(JobStatus.failed.rawValue == "failed")
    #expect(JobStatus.cancelled.rawValue == "cancelled")
    #expect(JobStatus.allCases.count == 5)
}

@Test func jobPayloadStorage() {
    let payload = Data("{\"meeting_id\": \"abc\"}".utf8)
    let job = Job(kind: "extract", payload: payload)
    #expect(job.payload == payload)
    #expect(job.kind == "extract")
}
