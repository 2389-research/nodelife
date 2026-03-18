// ABOUTME: Tests for the JobRunner actor
// ABOUTME: Verifies handler registration, job processing, and runner lifecycle

import Testing
import Foundation
import os
import GRDB
@testable import NodeLifeCore

@Test func jobRunnerRegistersHandlers() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)
    let runner = JobRunner(jobQueue: queue)

    let handler = ClosureJobHandler { _ in }
    await runner.register(kind: "test", handler: handler)

    let stats = await runner.stats()
    #expect(stats.registeredHandlers.contains("test"))
}

@Test func jobRunnerUnregistersHandlers() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)
    let runner = JobRunner(jobQueue: queue)

    let handler = ClosureJobHandler { _ in }
    await runner.register(kind: "test", handler: handler)
    await runner.unregister(kind: "test")

    let stats = await runner.stats()
    #expect(!stats.registeredHandlers.contains("test"))
}

@Test func jobRunnerStartsAndStops() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)
    let runner = JobRunner(jobQueue: queue, config: JobRunnerConfig(pollInterval: 0.1))

    try await runner.start()
    var stats = await runner.stats()
    #expect(stats.isRunning)

    await runner.stop()
    stats = await runner.stats()
    #expect(!stats.isRunning)
}

@Test func jobRunnerProcessesJob() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)
    let runner = JobRunner(jobQueue: queue, config: JobRunnerConfig(pollInterval: 0.05))

    let flag = OSAllocatedUnfairLock(initialState: false)
    let handler = ClosureJobHandler { _ in
        flag.withLock { $0 = true }
    }
    await runner.register(kind: "test", handler: handler)

    _ = try await queue.enqueue(kind: "test", payload: Data("{}".utf8))
    try await runner.start()

    // Wait for processing
    try await Task.sleep(for: .seconds(0.3))
    await runner.stop()

    #expect(flag.withLock { $0 } == true)
}

@Test func jobRunnerStatsTracksCounts() async throws {
    let db = try AppDatabase.makeInMemory()
    let queue = JobQueue(dbWriter: db.writer)
    let runner = JobRunner(jobQueue: queue, config: JobRunnerConfig(pollInterval: 0.05))

    let handler = ClosureJobHandler { _ in }
    await runner.register(kind: "test", handler: handler)

    _ = try await queue.enqueue(kind: "test", payload: Data())
    try await runner.start()

    try await Task.sleep(for: .seconds(0.3))
    await runner.stop()

    let stats = await runner.stats()
    #expect(stats.processedCount >= 1)
}

