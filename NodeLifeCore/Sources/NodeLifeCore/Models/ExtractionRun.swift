// ABOUTME: ExtractionRun record tracking a single LLM extraction pass over a meeting
// ABOUTME: Records model, prompt version, timing, and status for auditability

import Foundation
import GRDB

public enum ExtractionStatus: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case running
    case completed
    case failed
}

public struct ExtractionRun: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var meetingID: UUID
    public var model: String
    public var promptVersion: String
    public var passName: String?
    public var startedAt: Date
    public var completedAt: Date?
    public var status: ExtractionStatus
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        meetingID: UUID,
        model: String,
        promptVersion: String,
        passName: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        status: ExtractionStatus = .running,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.meetingID = meetingID
        self.model = model
        self.promptVersion = promptVersion
        self.passName = passName
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.errorMessage = errorMessage
    }
}

extension ExtractionRun: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "extraction_runs"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let meetingID = Column(CodingKeys.meetingID)
        public static let model = Column(CodingKeys.model)
        public static let promptVersion = Column(CodingKeys.promptVersion)
        public static let passName = Column(CodingKeys.passName)
        public static let startedAt = Column(CodingKeys.startedAt)
        public static let completedAt = Column(CodingKeys.completedAt)
        public static let status = Column(CodingKeys.status)
        public static let errorMessage = Column(CodingKeys.errorMessage)
    }

    public static let meeting = belongsTo(Meeting.self)
}
