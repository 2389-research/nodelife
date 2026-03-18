// ABOUTME: Actor-based async job processor that polls the queue and dispatches to registered handlers
// ABOUTME: Supports configurable concurrency, retry with exponential backoff, and graceful shutdown

import Foundation
import GRDB

/// Protocol for handling a specific kind of job
public protocol JobHandler: Sendable {
    func handle(job: Job) async throws
}

/// Simple closure-based job handler for inline use
public struct ClosureJobHandler: JobHandler {
    private let closure: @Sendable (Job) async throws -> Void

    public init(_ closure: @escaping @Sendable (Job) async throws -> Void) {
        self.closure = closure
    }

    public func handle(job: Job) async throws {
        try await closure(job)
    }
}

/// Configuration for the JobRunner
public struct JobRunnerConfig: Sendable {
    public var pollInterval: TimeInterval
    public var maxConcurrency: Int
    public var baseRetryDelay: TimeInterval
    public var maxRetryDelay: TimeInterval
    public var jobKinds: [String]

    public init(
        pollInterval: TimeInterval = 1.0,
        maxConcurrency: Int = 4,
        baseRetryDelay: TimeInterval = 1.0,
        maxRetryDelay: TimeInterval = 60.0,
        jobKinds: [String] = []
    ) {
        self.pollInterval = pollInterval
        self.maxConcurrency = maxConcurrency
        self.baseRetryDelay = baseRetryDelay
        self.maxRetryDelay = maxRetryDelay
        self.jobKinds = jobKinds
    }
}

/// Statistics about the runner state
public struct JobRunnerStats: Sendable {
    public var isRunning: Bool
    public var registeredHandlers: Set<String>
    public var activeJobs: Int
    public var processedCount: Int
    public var failedCount: Int
}

public actor JobRunner {
    private let jobQueue: JobQueue
    private let config: JobRunnerConfig
    private var handlers: [String: any JobHandler] = [:]
    private var isRunning: Bool = false
    private var runTask: Task<Void, Never>?
    private var activeJobs: Int = 0
    private var processedCount: Int = 0
    private var failedCount: Int = 0

    public init(jobQueue: JobQueue, config: JobRunnerConfig = JobRunnerConfig()) {
        self.jobQueue = jobQueue
        self.config = config
    }

    /// Register a handler for a specific job kind
    public func register(kind: String, handler: any JobHandler) {
        handlers[kind] = handler
    }

    /// Unregister a handler for a specific job kind
    public func unregister(kind: String) {
        handlers.removeValue(forKey: kind)
    }

    /// Get current runner statistics
    public func stats() -> JobRunnerStats {
        JobRunnerStats(
            isRunning: isRunning,
            registeredHandlers: Set(handlers.keys),
            activeJobs: activeJobs,
            processedCount: processedCount,
            failedCount: failedCount
        )
    }

    /// Start the job processing loop
    public func start() throws {
        guard !isRunning else { return }
        isRunning = true

        runTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    /// Stop the job processing loop gracefully
    public func stop() {
        isRunning = false
        runTask?.cancel()
        runTask = nil
    }

    private func runLoop() async {
        while !Task.isCancelled && isRunning {
            do {
                while activeJobs < config.maxConcurrency {
                    let kinds = config.jobKinds.isEmpty ? Array(handlers.keys) : config.jobKinds
                    guard let job = try await jobQueue.claim(kinds: kinds) else {
                        break
                    }
                    activeJobs += 1
                    Task { [weak self] in
                        guard let self else { return }
                        await self.process(job: job)
                    }
                }
            } catch {
                // Log and continue polling
            }

            do {
                try await Task.sleep(for: .seconds(config.pollInterval))
            } catch {
                break
            }
        }
    }

    private func process(job: Job) async {
        defer {
            Task { [weak self] in
                await self?.decrementActiveJobs()
            }
        }

        guard let handler = handlers[job.kind] else {
            try? await jobQueue.fail(jobID: job.id, error: "No handler registered for kind: \(job.kind)")
            failedCount += 1
            return
        }

        do {
            try await handler.handle(job: job)
            try await jobQueue.complete(jobID: job.id)
            processedCount += 1
        } catch {
            try? await jobQueue.fail(jobID: job.id, error: String(describing: error))
            failedCount += 1

            // Schedule retry if eligible
            await retryIfEligible(job: job)
        }
    }

    private func decrementActiveJobs() {
        activeJobs -= 1
    }

    private func retryIfEligible(job: Job) async {
        if job.attempts < job.maxAttempts {
            let delay = min(
                config.baseRetryDelay * pow(2.0, Double(job.attempts - 1)),
                config.maxRetryDelay
            )
            try? await Task.sleep(for: .seconds(delay))
            try? await jobQueue.retry(jobID: job.id)
        }
    }
}
