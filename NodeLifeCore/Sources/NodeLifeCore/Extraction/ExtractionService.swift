// ABOUTME: LLM-powered entity extraction service for meeting transcripts
// ABOUTME: Parses LLM JSON responses into Entity and Mention records via GRDB

import Foundation
import GRDB

// MARK: - Errors

public enum ExtractionError: Error, LocalizedError, Sendable {
    case invalidJSON(String)
    case noEntitiesFound
    case meetingNotFound(UUID)
    case invalidStatus(TranscriptStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail): return "Invalid JSON response: \(detail)"
        case .noEntitiesFound: return "No entities found in extraction response"
        case .meetingNotFound(let id): return "Meeting not found: \(id)"
        case .invalidStatus(let status): return "Invalid transcript status for extraction: \(status)"
        }
    }
}

// MARK: - JSON Response Types

public struct ExtractedMention: Codable, Sendable {
    public let surfaceForm: String
    public let chunkOrdinal: Int

    enum CodingKeys: String, CodingKey {
        case surfaceForm = "surface_form"
        case chunkOrdinal = "chunk_ordinal"
    }
}

public struct ExtractedEntity: Codable, Sendable {
    public let name: String
    public let type: String
    public let confidence: Double
    public let mentions: [ExtractedMention]
}

public struct EntityExtractionResponse: Codable, Sendable {
    public let entities: [ExtractedEntity]
}

// MARK: - ExtractionService

public struct ExtractionService: Sendable {
    public let database: AppDatabase
    public let llmClient: any LLMClient

    public init(database: AppDatabase, llmClient: any LLMClient) {
        self.database = database
        self.llmClient = llmClient
    }

    // MARK: - Entity Extraction

    /// Extracts entities from a meeting transcript using the LLM.
    /// The meeting must have transcriptStatus == .normalized before extraction.
    public func extractEntities(meetingId: UUID) async throws {
        let meeting: Meeting = try database.read { db in
            guard let meeting = try Meeting.fetchOne(db, key: meetingId) else {
                throw ExtractionError.meetingNotFound(meetingId)
            }
            return meeting
        }

        guard meeting.transcriptStatus == .normalized else {
            throw ExtractionError.invalidStatus(meeting.transcriptStatus)
        }

        let chunks: [MeetingChunk] = try database.read { db in
            try MeetingChunk
                .filter(MeetingChunk.Columns.meetingID == meetingId)
                .order(MeetingChunk.Columns.chunkIndex)
                .fetchAll(db)
        }

        let modelName = "default"
        let promptVersion = "v1"

        var extractionRun = ExtractionRun(
            meetingID: meetingId,
            model: modelName,
            promptVersion: promptVersion,
            passName: "entity_extraction",
            status: .running
        )

        try database.write { db in
            try extractionRun.insert(db)
        }

        do {
            let transcriptText = ExtractionPrompts.formatTranscriptForExtraction(chunks: chunks)
            let prompt = ExtractionPrompts.entityExtraction(
                meetingTitle: meeting.title,
                attendees: [],
                transcriptText: transcriptText
            )

            let response = try await llmClient.complete(
                prompt: prompt.userMessage,
                system: prompt.systemPrompt,
                maxTokens: 4096,
                temperature: 0.0,
                jsonMode: true
            )

            let extractedEntities = try Self.parseEntityResponse(response)

            if extractedEntities.isEmpty {
                throw ExtractionError.noEntitiesFound
            }

            try database.write { db in
                for extracted in extractedEntities {
                    let entity = try Self.findOrCreateEntity(
                        db: db,
                        name: extracted.name,
                        kind: Self.mapEntityType(extracted.type)
                    )

                    for mention in extracted.mentions {
                        let chunk = try MeetingChunk
                            .filter(MeetingChunk.Columns.meetingID == meetingId)
                            .filter(MeetingChunk.Columns.chunkIndex == mention.chunkOrdinal)
                            .fetchOne(db)

                        if let chunk = chunk {
                            var newMention = Mention(
                                entityID: entity.id,
                                meetingChunkID: chunk.id,
                                confidence: extracted.confidence,
                                extractionRunID: extractionRun.id
                            )
                            try newMention.insert(db)
                        }
                    }

                    var updatedEntity = entity
                    let totalMentions = try Mention
                        .filter(Mention.Columns.entityID == entity.id)
                        .fetchCount(db)
                    updatedEntity.mentionCount = totalMentions
                    updatedEntity.lastSeenAt = Date()
                    try updatedEntity.update(db)
                }

                extractionRun.status = .completed
                extractionRun.completedAt = Date()
                try extractionRun.update(db)

                var updatedMeeting = try Meeting.fetchOne(db, key: meetingId)!
                updatedMeeting.transcriptStatus = .extracted
                updatedMeeting.updatedAt = Date()
                try updatedMeeting.update(db)
            }
        } catch {
            try? database.write { db in
                extractionRun.status = .failed
                extractionRun.completedAt = Date()
                extractionRun.errorMessage = error.localizedDescription
                try extractionRun.update(db)
            }
            throw error
        }
    }

    // MARK: - Static Helpers

    /// Parses an LLM response string into extracted entities.
    /// Strips markdown code fences if present, then decodes JSON.
    public static func parseEntityResponse(_ response: String) throws -> [ExtractedEntity] {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences (```json ... ``` or ``` ... ```)
        if cleaned.hasPrefix("```") {
            // Remove opening fence (with optional language tag)
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            // Remove closing fence
            if let lastFence = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[..<lastFence.lowerBound])
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw ExtractionError.invalidJSON("Could not convert response to data")
        }

        do {
            let decoded = try JSONDecoder().decode(EntityExtractionResponse.self, from: data)
            return decoded.entities
        } catch {
            throw ExtractionError.invalidJSON(error.localizedDescription)
        }
    }

    /// Maps a string type name from the LLM response to an EntityKind enum value.
    /// Handles snake_case variants and common abbreviations.
    public static func mapEntityType(_ type: String) -> EntityKind {
        switch type.lowercased() {
        case "person": return .person
        case "organization", "org": return .organization
        case "project": return .project
        case "concept": return .concept
        case "topic": return .topic
        case "place": return .place
        case "actionitem", "action_item": return .actionItem
        case "blogidea", "blog_idea": return .blogIdea
        case "idea": return .idea
        default: return .other
        }
    }

    /// Finds an existing entity by canonical name and kind, or creates a new one.
    public static func findOrCreateEntity(
        db: Database,
        name: String,
        kind: EntityKind
    ) throws -> Entity {
        let canonicalName = name.lowercased()

        if let existing = try Entity
            .filter(Entity.Columns.canonicalName == canonicalName)
            .filter(Entity.Columns.kind == kind)
            .fetchOne(db)
        {
            return existing
        }

        var entity = Entity(name: name, kind: kind)
        try entity.insert(db)
        return entity
    }
}
