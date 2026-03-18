// ABOUTME: Job record for the internal task queue supporting background work
// ABOUTME: Tracks status, priority, attempts, and scheduling for reliable job processing

import Foundation
import GRDB

public enum JobStatus: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

public struct Job: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: String
    public var payload: Data
    public var status: JobStatus
    public var priority: Int
    public var attempts: Int
    public var maxAttempts: Int
    public var lastError: String?
    public var createdAt: Date
    public var scheduledAt: Date
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: String,
        payload: Data,
        status: JobStatus = .pending,
        priority: Int = 0,
        attempts: Int = 0,
        maxAttempts: Int = 3,
        lastError: String? = nil,
        createdAt: Date = Date(),
        scheduledAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.status = status
        self.priority = priority
        self.attempts = attempts
        self.maxAttempts = maxAttempts
        self.lastError = lastError
        self.createdAt = createdAt
        self.scheduledAt = scheduledAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

extension Job: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "jobs"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let kind = Column(CodingKeys.kind)
        public static let payload = Column(CodingKeys.payload)
        public static let status = Column(CodingKeys.status)
        public static let priority = Column(CodingKeys.priority)
        public static let attempts = Column(CodingKeys.attempts)
        public static let maxAttempts = Column(CodingKeys.maxAttempts)
        public static let lastError = Column(CodingKeys.lastError)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let scheduledAt = Column(CodingKeys.scheduledAt)
        public static let startedAt = Column(CodingKeys.startedAt)
        public static let completedAt = Column(CodingKeys.completedAt)
    }
}
